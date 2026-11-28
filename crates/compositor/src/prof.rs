//! `GLOVE_PROF=1`: a cada 2 segundos, o registro diz quantos quadros o
//! compositor fez e quanto tempo gastou preparando (desenhos na CPU: Dock,
//! barra, títulos), montando a lista do quadro e mandando desenhar (GPU).

use std::cell::RefCell;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

#[derive(Default)]
struct Acc {
    since: Option<Instant>,
    frames: u32,
    prep: Duration,
    prep_max: Duration,
    build: Duration,
    render: Duration,
    render_max: Duration,
}

thread_local! {
    static ACC: RefCell<Acc> = RefCell::new(Acc::default());
    /// The audit (tools/gpu-audit): every frame since the last mark (prepare, build,
    /// render), for the numbers of one scenario.
    static MARK: RefCell<Option<(String, Instant, Vec<(Duration, Duration, Duration)>)>> = const { RefCell::new(None) };
}

/// Audit: a scenario starts (`profmark NAME` of the debug control).
pub fn mark(name: &str) {
    MARK.with(|m| *m.borrow_mut() = Some((name.to_string(), Instant::now(), Vec::new())));
    tracing::info!("PROFMARK {name}");
}

/// Audit: the numbers of the scenario since the mark (`profdump`), in one line.
pub fn dump() {
    MARK.with(|m| {
        let Some((name, since, frames)) = m.borrow_mut().take() else { return };
        let ms = |d: Duration| d.as_secs_f64() * 1000.0;
        let stat = |mut v: Vec<f64>| -> (f64, f64, f64) {
            if v.is_empty() {
                return (0.0, 0.0, 0.0);
            }
            v.sort_by(|a, b| a.total_cmp(b));
            let avg = v.iter().sum::<f64>() / v.len() as f64;
            let p95 = v[((v.len() as f64 * 0.95).ceil() as usize).saturating_sub(1).min(v.len() - 1)];
            (avg, p95, *v.last().unwrap())
        };
        let (pa, pp, pm) = stat(frames.iter().map(|f| ms(f.0)).collect());
        let (ba, _, _) = stat(frames.iter().map(|f| ms(f.1)).collect());
        let (ra, rp, rm) = stat(frames.iter().map(|f| ms(f.2)).collect());
        let el = since.elapsed().as_secs_f64();
        tracing::info!(
            "PROFDUMP {name} frames={} fps={:.1} prep_avg={pa:.2} prep_p95={pp:.2} prep_max={pm:.2} build_avg={ba:.2} render_avg={ra:.2} render_p95={rp:.2} render_max={rm:.2}",
            frames.len(),
            frames.len() as f64 / el.max(0.001)
        );
    });
}

fn mark_frame(prep: Option<Duration>, build: Option<Duration>, render: Option<Duration>) {
    MARK.with(|m| {
        if let Some((_, _, v)) = m.borrow_mut().as_mut() {
            match (prep, build, render) {
                (Some(p), _, _) => v.push((p, Duration::ZERO, Duration::ZERO)),
                (_, Some(b), _) => {
                    if let Some(l) = v.last_mut() {
                        l.1 += b;
                    }
                }
                (_, _, Some(r)) => {
                    if let Some(l) = v.last_mut() {
                        l.2 += r;
                    }
                }
                _ => {}
            }
        }
    });
}

pub fn on() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var_os("GLOVE_PROF").is_some())
}

/// Tempo de preparar o quadro (conta um quadro).
pub fn prep(d: Duration) {
    mark_frame(Some(d), None, None);
    ACC.with(|a| {
        let mut a = a.borrow_mut();
        a.frames += 1;
        a.prep += d;
        a.prep_max = a.prep_max.max(d);
    });
    report();
}

pub fn build(d: Duration) {
    mark_frame(None, Some(d), None);
    ACC.with(|a| a.borrow_mut().build += d);
}

pub fn render(d: Duration) {
    mark_frame(None, None, Some(d));
    ACC.with(|a| {
        let mut a = a.borrow_mut();
        a.render += d;
        a.render_max = a.render_max.max(d);
    });
}

fn report() {
    ACC.with(|a| {
        let mut a = a.borrow_mut();
        let since = *a.since.get_or_insert_with(Instant::now);
        let el = since.elapsed();
        if el < Duration::from_secs(2) {
            return;
        }
        let n = a.frames.max(1);
        tracing::info!(
            "perfil: {:.1} quadros/s | preparar {:?} (pior {:?}) | montar {:?} | desenhar {:?} (pior {:?}) | CPU no laço ≈ {:.0}%",
            a.frames as f64 / el.as_secs_f64(),
            a.prep / n,
            a.prep_max,
            a.build / n,
            a.render / n,
            a.render_max,
            (a.prep + a.build + a.render).as_secs_f64() / el.as_secs_f64() * 100.0
        );
        *a = Acc { since: Some(Instant::now()), ..Acc::default() };
    });
}
