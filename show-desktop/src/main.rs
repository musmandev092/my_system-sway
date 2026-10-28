use std::{env, fs, path::PathBuf, sync::OnceLock};

use cosmic_protocols::{
    toplevel_info::v1::client::{zcosmic_toplevel_handle_v1, zcosmic_toplevel_info_v1},
    toplevel_management::v1::client::zcosmic_toplevel_manager_v1,
};
use wayland_client::{
    Connection, Dispatch, Proxy, QueueHandle, event_created_child,
    globals::{GlobalListContents, registry_queue_init},
    protocol::{wl_registry, wl_seat},
};
use wayland_protocols::ext::foreign_toplevel_list::v1::client::{
    ext_foreign_toplevel_handle_v1::{self, ExtForeignToplevelHandleV1},
    ext_foreign_toplevel_list_v1::{self, ExtForeignToplevelListV1},
};
use zcosmic_toplevel_handle_v1::{State as TState, ZcosmicToplevelHandleV1};
use zcosmic_toplevel_info_v1::ZcosmicToplevelInfoV1;
use zcosmic_toplevel_manager_v1::ZcosmicToplevelManagerV1;

#[derive(Default)]
struct Window {
    identifier: String,
    cosmic: Option<ZcosmicToplevelHandleV1>,
    minimized: bool,
    activated: bool,
    got_state: bool,
    closed: bool,
}

struct App {
    info: ZcosmicToplevelInfoV1,
    windows: Vec<Window>,
}

fn state_file() -> PathBuf {
    let dir = env::var_os("XDG_RUNTIME_DIR").unwrap_or_else(|| "/tmp".into());
    PathBuf::from(dir).join("show-desktop.state")
}

fn main() {
    let conn = Connection::connect_to_env().expect("no Wayland display");
    let (globals, mut queue) = registry_queue_init::<App>(&conn).expect("registry");
    let qh = queue.handle();

    let bind_err = |name: &str| format!("compositor lacks {name} (is this COSMIC?)");
    let list: ExtForeignToplevelListV1 =
        globals.bind(&qh, 1..=1, ()).expect(&bind_err("ext_foreign_toplevel_list_v1"));
    let info: ZcosmicToplevelInfoV1 =
        globals.bind(&qh, 2..=3, ()).expect(&bind_err("zcosmic_toplevel_info_v1"));
    let manager: ZcosmicToplevelManagerV1 =
        globals.bind(&qh, 1..=4, ()).expect(&bind_err("zcosmic_toplevel_manager_v1"));
    let seat: Option<wl_seat::WlSeat> = globals.bind(&qh, 1..=1, ()).ok();

    let mut app = App { info, windows: Vec::new() };

    queue.roundtrip(&mut app).expect("roundtrip");
    for _ in 0..50 {
        queue.roundtrip(&mut app).expect("roundtrip");
        if app.windows.iter().all(|w| w.got_state || w.closed) {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    let _ = list;

    let live: Vec<&Window> = app.windows.iter().filter(|w| !w.closed && w.cosmic.is_some()).collect();
    let status_only = env::args().any(|a| a == "--status");
    if status_only || env::var_os("SHOW_DESKTOP_DEBUG").is_some() {
        for w in &live {
            eprintln!("{} minimized={} active={}", w.identifier, w.minimized, w.activated);
        }
    }
    if status_only {
        return;
    }
    let visible: Vec<&&Window> = live.iter().filter(|w| !w.minimized).collect();

    if !visible.is_empty() {

        let mut ids: Vec<&str> = visible.iter().filter(|w| !w.activated).map(|w| w.identifier.as_str()).collect();
        ids.extend(visible.iter().filter(|w| w.activated).map(|w| w.identifier.as_str()));
        for w in &visible {
            manager.set_minimized(w.cosmic.as_ref().unwrap());
        }
        let _ = fs::write(state_file(), ids.join("\n"));
    } else {

        let saved = fs::read_to_string(state_file()).unwrap_or_default();
        let mut last = None;
        for id in saved.lines() {
            if let Some(w) = live.iter().find(|w| w.identifier == id) {
                let h = w.cosmic.as_ref().unwrap();
                manager.unset_minimized(h);
                last = Some(h);
            }
        }
        if let (Some(h), Some(seat)) = (last, &seat) {
            manager.activate(h, seat);
        }
        let _ = fs::remove_file(state_file());
    }
    queue.roundtrip(&mut app).expect("flush");
}

impl Dispatch<ExtForeignToplevelListV1, ()> for App {
    fn event(app: &mut Self, _: &ExtForeignToplevelListV1, event: ext_foreign_toplevel_list_v1::Event,
             _: &(), _: &Connection, qh: &QueueHandle<Self>) {
        if let ext_foreign_toplevel_list_v1::Event::Toplevel { toplevel } = event {
            let idx = app.windows.len();
            let cosmic = app.info.get_cosmic_toplevel(&toplevel, qh, idx);
            app.windows.push(Window { cosmic: Some(cosmic), ..Default::default() });

            let _ = toplevel.data::<OnceLock<usize>>().unwrap().set(idx);
        }
    }
    event_created_child!(App, ExtForeignToplevelListV1, [
        ext_foreign_toplevel_list_v1::EVT_TOPLEVEL_OPCODE => (ExtForeignToplevelHandleV1, OnceLock::new())
    ]);
}

impl Dispatch<ExtForeignToplevelHandleV1, OnceLock<usize>> for App {
    fn event(app: &mut Self, _: &ExtForeignToplevelHandleV1, event: ext_foreign_toplevel_handle_v1::Event,
             idx: &OnceLock<usize>, _: &Connection, _: &QueueHandle<Self>) {
        let Some(w) = idx.get().and_then(|i| app.windows.get_mut(*i)) else { return };
        match event {
            ext_foreign_toplevel_handle_v1::Event::Identifier { identifier } => w.identifier = identifier,
            ext_foreign_toplevel_handle_v1::Event::Closed => w.closed = true,
            _ => {}
        }
    }
}

impl Dispatch<ZcosmicToplevelHandleV1, usize> for App {
    fn event(app: &mut Self, _: &ZcosmicToplevelHandleV1, event: zcosmic_toplevel_handle_v1::Event,
             idx: &usize, _: &Connection, _: &QueueHandle<Self>) {
        if let zcosmic_toplevel_handle_v1::Event::State { state } = event {
            let w = &mut app.windows[*idx];
            w.got_state = true;
            w.minimized = false;
            w.activated = false;
            for chunk in state.chunks_exact(4) {
                let v = u32::from_ne_bytes(chunk.try_into().unwrap());
                match TState::try_from(v) {
                    Ok(TState::Minimized) => w.minimized = true,
                    Ok(TState::Activated) => w.activated = true,
                    _ => {}
                }
            }
        }
    }
}

macro_rules! ignore {
    ($($t:ty),*) => {$(
        impl Dispatch<$t, ()> for App {
            fn event(_: &mut Self, _: &$t, _: <$t as Proxy>::Event,
                     _: &(), _: &Connection, _: &QueueHandle<Self>) {}
        }
    )*};
}
ignore!(ZcosmicToplevelInfoV1, ZcosmicToplevelManagerV1, wl_seat::WlSeat);

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for App {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event,
             _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
