// Home screen for Nava360 — app bar + dashboard + bottom nav (Home/Leave/Task)
// + left navigation drawer (profile on top, menus: Attendance/Leave/Task/Holiday).
// Mirrors lib/features/home/home_shell.dart + dashboard_screen.dart.
// Renders only after sign-in (lazy-mounted by Flow). Reads shared tokens from window.

// ── Live attendance hero (owns its own ticking clock so the rest of the
// home screen doesn't re-render every second) ──
function ShiftHero({ checkedIn, inTime, outTime, inEpoch, frozenSecs, onToggle, C }) {
  const { useState, useEffect } = React;
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    if (!checkedIn) return undefined;
    setNow(Date.now());
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [checkedIn]);
  const secs = (checkedIn && inEpoch) ? Math.max(0, Math.floor((now - inEpoch) / 1000)) : (frozenSecs || 0);
  const hhmmss = (x) => [Math.floor(x / 3600), Math.floor((x % 3600) / 60), x % 60].map((n) => String(n).padStart(2, '0')).join(':');
  const finger = <path d="M12 11v3m-4-3a4 4 0 018 0m-10 0a6 6 0 0112 0c0 3-1 5-1 5M7 14c0 2 .5 3 .5 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" fill="none"/>;
  const statusLabel = checkedIn ? 'ON SHIFT' : (outTime ? 'SHIFT COMPLETE' : 'NOT CHECKED IN');
  const btnLabel = checkedIn ? 'Check out' : (outTime ? 'Check in again' : 'Check in now');
  const TimeChip = ({ label, value, dot }) => (
    <div style={{ flex: 1, padding: '10px 12px', borderRadius: 13, background: 'rgba(255,255,255,0.16)', border: '1px solid rgba(255,255,255,0.28)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 10.5, fontWeight: 700, letterSpacing: 0.4, opacity: 0.85 }}>
        <span style={{ width: 6, height: 6, borderRadius: '50%', background: dot }} />{label}
      </div>
      <div style={{ fontSize: 17, fontWeight: 800, marginTop: 3, fontVariantNumeric: 'tabular-nums' }}>{value || '— : —'}</div>
    </div>
  );
  return (
    <div style={{ borderRadius: 20, padding: 20, color: '#fff', position: 'relative', overflow: 'hidden',
      background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 55%,#06B6D4 130%)', boxShadow: '0 18px 38px rgba(79,70,229,0.32)' }}>
      <div style={{ position: 'absolute', width: 180, height: 180, borderRadius: '50%', top: -70, right: -50,
        background: 'radial-gradient(circle,rgba(255,255,255,0.18),transparent 70%)' }} />
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', position: 'relative' }}>
        <div style={{ fontSize: 12.5, fontWeight: 700, letterSpacing: 0.4, opacity: 0.9 }}>{statusLabel}</div>
        <span style={{ padding: '3px 9px', borderRadius: 999, fontSize: 10.5, fontWeight: 800, color: '#fff', background: 'rgba(255,255,255,0.22)', border: '1px solid rgba(255,255,255,0.4)' }}>{checkedIn ? 'Live' : (outTime ? 'Done' : 'Idle')}</span>
      </div>
      <div style={{ fontSize: 44, fontWeight: 800, letterSpacing: -1, marginTop: 8, fontVariantNumeric: 'tabular-nums', position: 'relative' }}>{hhmmss(secs)}</div>
      <div style={{ fontSize: 12.5, opacity: 0.85, marginTop: 2, position: 'relative' }}>
        {checkedIn ? 'Hyderabad HQ · worked today' : (outTime ? 'Total hours worked today' : 'Tap below to start your shift')}
      </div>
      <div style={{ display: 'flex', gap: 10, marginTop: 14, position: 'relative' }}>
        <TimeChip label="CHECK IN" value={inTime} dot="#34D399" />
        <TimeChip label="CHECK OUT" value={outTime} dot="#FCA5A5" />
      </div>
      <button onClick={onToggle} style={{ marginTop: 16, width: '100%', cursor: 'pointer', padding: '13px', borderRadius: 12,
        background: checkedIn ? 'rgba(255,255,255,0.18)' : '#fff', color: checkedIn ? '#fff' : C.primaryDark,
        fontFamily: 'Roboto, system-ui', fontSize: 14.5, fontWeight: 800, letterSpacing: 0.2,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        border: checkedIn ? '1px solid rgba(255,255,255,0.4)' : 'none', position: 'relative' }}>
        <svg width="19" height="19" viewBox="0 0 24 24" style={{ color: checkedIn ? '#fff' : C.primaryDark }}>{finger}</svg>{btnLabel}
      </button>
    </div>
  );
}

// ── Apply-for-leave slide-up sheet (top-level → keeps form state across
// parent re-renders) ──
function ApplyLeaveSheet({ open, onClose, onSubmit }) {
  const { useState, useEffect } = React;
  const C = window.NavaColors || { primary:'#4F46E5', primaryDark:'#3730A3', accent:'#06B6D4', ink:'#0F172A', inkSoft:'#334155', muted:'#64748B' };
  const success = '#10B981', warning = '#F59E0B', info = '#3B82F6';
  const [type, setType] = useState('Casual');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [reason, setReason] = useState('');
  const [err, setErr] = useState(null);
  const [busy, setBusy] = useState(false);
  const [ok, setOk] = useState(false);
  useEffect(() => { if (open) { setType('Casual'); setFrom(''); setTo(''); setReason(''); setErr(null); setBusy(false); setOk(false); } }, [open]);
  const days = (from && to) ? Math.max(0, Math.round((new Date(to) - new Date(from)) / 86400000) + 1) : 0;
  const submit = () => {
    if (!from || !to) { setErr('Select both start and end dates.'); return; }
    if (new Date(to) < new Date(from)) { setErr('End date can’t be before the start date.'); return; }
    if (!reason.trim()) { setErr('Please add a reason for your leave.'); return; }
    setErr(null); setBusy(true);
    setTimeout(() => { setBusy(false); setOk(true); onSubmit({ type, from, to, days, reason: reason.trim() }); setTimeout(onClose, 950); }, 1100);
  };
  const types = [['Casual', success], ['Sick', warning], ['Earned', info], ['Unpaid', C.muted]];
  const lbl = (t) => <div style={{ fontSize: 12.5, fontWeight: 700, color: C.ink, margin: '0 0 8px' }}>{t}</div>;
  const inputBase = { width: '100%', boxSizing: 'border-box', padding: '12px 12px', borderRadius: 11,
    fontFamily: 'Roboto, system-ui', fontSize: 13.5, color: C.ink, background: 'rgba(255,255,255,0.85)',
    border: '1px solid rgba(15,23,42,0.12)', outline: 'none' };
  return (
    <React.Fragment>
      <div onClick={onClose} style={{ position: 'absolute', inset: 0, zIndex: 55, background: 'rgba(15,23,42,0.42)',
        opacity: open ? 1 : 0, pointerEvents: open ? 'auto' : 'none', transition: 'opacity .3s ease' }} />
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 60, maxHeight: '86%', overflowY: 'auto',
        transform: `translateY(${open ? 0 : 110}%)`, transition: 'transform .36s cubic-bezier(.4,0,.2,1)',
        borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: '12px 20px 30px',
        background: 'rgba(255,255,255,0.9)', backdropFilter: 'blur(24px)', WebkitBackdropFilter: 'blur(24px)',
        boxShadow: '0 -16px 44px rgba(15,23,42,0.22)' }}>
        <div style={{ width: 40, height: 5, borderRadius: 999, background: 'rgba(15,23,42,0.18)', margin: '0 auto 16px' }} />
        <div style={{ fontSize: 19, fontWeight: 800, color: C.ink, letterSpacing: -0.3 }}>Apply for leave</div>
        <div style={{ fontSize: 12.5, color: C.muted, marginTop: 3, marginBottom: 18 }}>Request time off — your manager will be notified.</div>

        {lbl('Leave type')}
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 16 }}>
          {types.map(([t, c]) => {
            const on = type === t;
            return (
              <button key={t} onClick={() => setType(t)} style={{ cursor: 'pointer', padding: '9px 14px', borderRadius: 999,
                fontFamily: 'Roboto, system-ui', fontSize: 13, fontWeight: 700,
                color: on ? '#fff' : C.inkSoft, background: on ? c : 'rgba(255,255,255,0.7)',
                border: '1px solid ' + (on ? c : 'rgba(15,23,42,0.12)') }}>{t}</button>
            );
          })}
        </div>

        <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
          <div style={{ flex: 1 }}>{lbl('From')}<input type="date" value={from} onChange={(e) => setFrom(e.target.value)} style={inputBase} /></div>
          <div style={{ flex: 1 }}>{lbl('To')}<input type="date" value={to} onChange={(e) => setTo(e.target.value)} style={inputBase} /></div>
        </div>
        {days > 0 && (
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 12px', borderRadius: 999,
            background: C.primary + '14', border: '1px solid ' + C.primary + '33', marginBottom: 16 }}>
            <span style={{ fontSize: 12.5, fontWeight: 700, color: C.primary }}>{days} day{days === 1 ? '' : 's'} of leave</span>
          </div>
        )}

        {lbl('Reason')}
        <textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} placeholder="Briefly describe your reason…"
          style={{ ...inputBase, resize: 'none', lineHeight: 1.4 }} />

        {err && (
          <div style={{ marginTop: 14, padding: 12, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8,
            background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.25)' }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="#EF4444" strokeWidth="1.8"/><path d="M12 7v6M12 16.5v.5" stroke="#EF4444" strokeWidth="1.8" strokeLinecap="round"/></svg>
            <span style={{ color: '#EF4444', fontSize: 13, fontWeight: 500 }}>{err}</span>
          </div>
        )}

        <button onClick={submit} disabled={busy || ok} style={{ width: '100%', marginTop: 18, cursor: busy ? 'default' : 'pointer',
          padding: '16px', borderRadius: 13, border: 'none', color: '#fff', fontFamily: 'Roboto, system-ui', fontSize: 15, fontWeight: 700,
          letterSpacing: 0.3, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          background: ok ? 'linear-gradient(135deg,#10B981,#34D399)' : 'linear-gradient(135deg,#4F46E5 0%,#06B6D4 100%)',
          boxShadow: '0 12px 28px rgba(79,70,229,0.4)', transition: 'background .3s ease' }}>
          {busy
            ? <span style={{ width: 20, height: 20, border: '2.4px solid rgba(255,255,255,0.4)', borderTopColor: '#fff', borderRadius: '50%', display: 'inline-block', animation: 'navaspin 0.7s linear infinite' }} />
            : ok
              ? <React.Fragment><svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 13l4 4L19 7" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/></svg>Request submitted</React.Fragment>
              : <React.Fragment>Submit request<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 12h14M13 6l6 6-6 6" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/></svg></React.Fragment>}
        </button>
      </div>
    </React.Fragment>
  );
}

// ── Employee profile (slides in from the drawer's profile header) ──
function EmployeeProfile({ open, onBack, name, initials, role, empId }) {
  const C = window.NavaColors || { primary:'#4F46E5', primaryDark:'#3730A3', accent:'#06B6D4', pink:'#EC4899', violet:'#8B5CF6', ink:'#0F172A', inkSoft:'#334155', muted:'#64748B' };
  const Mesh = window.NavaMesh;
  const success = '#10B981', info = '#3B82F6', warning = '#F59E0B';
  const S = ({ d, size = 18, color = 'currentColor' }) => <svg width={size} height={size} viewBox="0 0 24 24" style={{ color, display: 'block' }}>{d}</svg>;
  const I = {
    badge: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="M6 16c.5-1.5 1.7-2 3-2s2.5.5 3 2M15 9h4M15 13h3" strokeLinecap="round"/></g>,
    phone: <path d="M5 4h3l2 5-2 1a11 11 0 005 5l1-2 5 2v3a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"/>,
    brief: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 012-2h4a2 2 0 012 2v2" strokeLinecap="round"/></g>,
    build: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h2M8 11h2M8 15h2M14 7h2M14 11h2M14 15h2" strokeLinecap="round"/></g>,
    cal: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 9h18M8 3v4M16 3v4" strokeLinecap="round"/></g>,
    person: <g fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-3.3 3.6-6 8-6s8 2.7 8 6" strokeLinecap="round"/></g>,
    mail: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6" strokeLinecap="round" strokeLinejoin="round"/></g>,
    pin: <path d="M12 21s7-6.5 7-12a7 7 0 10-14 0c0 5.5 7 12 7 12z M12 9a2 2 0 100 4 2 2 0 000-4z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"/>,
    back: <path d="M10 2L2 10l8 8" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    edit: <path d="M4 20h4L18 10l-4-4L4 16v4z M14 6l4 4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>,
  };
  const rows = [
    ['Employee ID', empId, C.accent, I.badge],
    ['Mobile number', '+91 98765 43210', success, I.phone],
    ['Designation', role, info, I.brief],
    ['Department', 'Livelihoods · Field Ops', C.primary, I.build],
    ['Work location', 'Hyderabad HQ', C.violet, I.pin],
    ['Date of joining', '14 Mar 2023', warning, I.cal],
    ['Reporting manager', 'Anil Kumar', C.pink, I.person],
  ];
  const stats = [['18', 'Present', success], ['9', 'Leave bal.', info], ['24', 'Tasks done', C.primary]];
  const card = { borderRadius: 16, background: 'rgba(255,255,255,0.62)', backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)', border: '1px solid rgba(255,255,255,0.7)', boxShadow: '0 12px 30px rgba(16,24,40,0.08)' };
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 70, fontFamily: 'Roboto, system-ui', overflow: 'hidden',
      transform: `translateX(${open ? 0 : 100}%)`, transition: 'transform .4s cubic-bezier(.4,0,.2,1)',
      pointerEvents: open ? 'auto' : 'none' }}>
      {Mesh ? <Mesh intensity={0.7} veil={false} /> : <div style={{ position: 'absolute', inset: 0, background: '#EEF1F8' }} />}

      {/* single natural-flow scroll container (header scrolls with content) */}
      <div style={{ position: 'absolute', inset: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
        {/* hero */}
        <div style={{ paddingTop: 50, paddingBottom: 46, color: '#fff', position: 'relative', overflow: 'hidden',
          background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 55%,#06B6D4 135%)',
          borderBottomLeftRadius: 30, borderBottomRightRadius: 30 }}>
          <div style={{ position: 'absolute', width: 220, height: 220, borderRadius: '50%', top: -80, right: -60, background: 'radial-gradient(circle,rgba(255,255,255,0.18),transparent 70%)' }} />
          <div style={{ position: 'absolute', width: 160, height: 160, borderRadius: '50%', bottom: -50, left: -40, background: 'radial-gradient(circle,rgba(6,182,212,0.4),transparent 70%)' }} />
          <div style={{ display: 'flex', alignItems: 'center', padding: '0 12px', position: 'relative' }}>
            <button onClick={onBack} style={{ width: 40, height: 40, borderRadius: 999, cursor: 'pointer',
              background: 'rgba(255,255,255,0.18)', border: '1px solid rgba(255,255,255,0.32)', color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}><S d={I.back} size={16} /></button>
            <div style={{ flex: 1, textAlign: 'center', fontSize: 15.5, fontWeight: 700 }}>Profile</div>
            <button style={{ width: 40, height: 40, borderRadius: 999, cursor: 'pointer',
              background: 'rgba(255,255,255,0.18)', border: '1px solid rgba(255,255,255,0.32)', color: '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}><S d={I.edit} size={17} /></button>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', position: 'relative', marginTop: 10 }}>
            <div style={{ position: 'relative' }}>
              <div style={{ width: 88, height: 88, borderRadius: 28, background: 'rgba(255,255,255,0.22)', border: '2px solid rgba(255,255,255,0.55)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 32, fontWeight: 800,
                boxShadow: '0 16px 34px rgba(0,0,0,0.22)' }}>{initials}</div>
              <span style={{ position: 'absolute', bottom: 4, right: 4, width: 16, height: 16, borderRadius: '50%', background: '#34D399', border: '2.5px solid #4338CA' }} />
            </div>
            <div style={{ fontSize: 22, fontWeight: 800, letterSpacing: -0.3, marginTop: 14 }}>{name}</div>
            <div style={{ fontSize: 13, opacity: 0.9, marginTop: 3 }}>{role} · ID {empId}</div>
          </div>
        </div>

        {/* overlapping stats card */}
        <div style={{ padding: '0 16px', marginTop: -28, position: 'relative' }}>
          <div style={{ ...card, display: 'flex', padding: '14px 6px' }}>
            {stats.map(([v, l, c], i) => (
              <div key={l} style={{ flex: 1, textAlign: 'center', borderLeft: i ? '1px solid rgba(15,23,42,0.08)' : 'none' }}>
                <div style={{ fontSize: 21, fontWeight: 800, color: c, letterSpacing: -0.4 }}>{v}</div>
                <div style={{ fontSize: 11, color: C.muted, fontWeight: 600, marginTop: 2 }}>{l}</div>
              </div>
            ))}
          </div>
        </div>

        {/* employee details */}
        <div style={{ padding: '22px 16px 30px' }}>
          <div style={{ fontSize: 11, fontWeight: 800, letterSpacing: 1.2, color: C.muted, margin: '0 4px 10px' }}>EMPLOYEE DETAILS</div>
          <div style={{ ...card, padding: 4 }}>
            {rows.map((r, i, a) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 12px',
                borderBottom: i < a.length - 1 ? '1px solid rgba(15,23,42,0.06)' : 'none' }}>
                <div style={{ width: 38, height: 38, borderRadius: 11, background: r[2] + '1f', color: r[2], border: '1px solid ' + r[2] + '33',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><S d={r[3]} size={18} /></div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11, color: C.muted, fontWeight: 600 }}>{r[0]}</div>
                  <div style={{ fontSize: 14, fontWeight: 700, color: C.ink, marginTop: 1 }}>{r[1]}</div>
                </div>
              </div>
            ))}
          </div>
          <div style={{ textAlign: 'center', color: C.muted, fontSize: 12, fontWeight: 500, marginTop: 20 }}>Nava360 · v1.0</div>
        </div>
      </div>
    </div>
  );
}

function HomeScreen({ username, onSignOut }) {
  const { useState, useEffect, useRef } = React;
  const C = window.NavaColors || { primary:'#4F46E5', primaryDark:'#3730A3', accent:'#06B6D4', pink:'#EC4899',
    violet:'#8B5CF6', ink:'#0F172A', inkSoft:'#334155', muted:'#64748B', teal:'#14B8A6', green:'#10B981' };
  const Mesh = window.NavaMesh;
  const LOGO = 'assets/logo-mark.png';
  const success = '#10B981', info = '#3B82F6', warning = '#F59E0B', danger = '#EF4444';

  const name = (username && username.trim()) || 'Priya Reddy';
  const initials = name.split(/[\s.@_]+/).filter(Boolean).slice(0, 2).map(s => s[0].toUpperCase()).join('') || 'PR';
  const role = 'Field Executive';
  const empId = 'NAV-1042';

  const [section, setSection] = useState('home'); // home | leave | task | attendance | holiday
  const [drawer, setDrawer] = useState(false);
  const [checkedIn, setCheckedIn] = useState(false);
  const [inTime, setInTime] = useState(null);
  const [outTime, setOutTime] = useState(null);
  const [inEpoch, setInEpoch] = useState(null);
  const [frozenSecs, setFrozenSecs] = useState(0);
  const [applyOpen, setApplyOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [resignSubmitted, setResignSubmitted] = useState(false);
  const fmtTime = (d) => d.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true });
  const toggleShift = () => {
    const now = new Date();
    if (!checkedIn) { setInTime(fmtTime(now)); setOutTime(null); setInEpoch(now.getTime()); setFrozenSecs(0); setCheckedIn(true); }
    else { setOutTime(fmtTime(now)); setFrozenSecs(Math.floor((now.getTime() - (inEpoch || now.getTime())) / 1000)); setCheckedIn(false); }
  };

  // ── small building blocks ─────────────────────────────────────────
  const Glass = ({ children, style, pad = 16 }) => (
    <div style={{ borderRadius: 16, padding: pad, background: 'rgba(255,255,255,0.55)',
      backdropFilter: 'blur(14px)', WebkitBackdropFilter: 'blur(14px)',
      border: '1px solid rgba(255,255,255,0.6)', boxShadow: '0 8px 22px rgba(16,24,40,0.06)', ...style }}>{children}</div>
  );
  const Avatar = ({ size = 36, radius = 11, fs = 14 }) => (
    <div style={{ width: size, height: size, borderRadius: radius, flexShrink: 0,
      background: 'linear-gradient(135deg,#4F46E5,#06B6D4)', color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: fs,
      boxShadow: '0 4px 12px rgba(79,70,229,0.35)' }}>{initials}</div>
  );
  const Pill = ({ label, color }) => (
    <span style={{ padding: '3px 9px', borderRadius: 999, fontSize: 10.5, fontWeight: 800, letterSpacing: 0.2,
      color, background: color + '24', border: '1px solid ' + color + '4d' }}>{label}</span>
  );
  const SectionHead = ({ title, sub, trailing }) => (
    <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', margin: '0 2px 10px' }}>
      <div>
        <div style={{ fontSize: 16, fontWeight: 800, color: C.ink, letterSpacing: -0.2 }}>{title}</div>
        {sub && <div style={{ fontSize: 12, color: C.muted, marginTop: 2 }}>{sub}</div>}
      </div>
      {trailing && <div style={{ fontSize: 11.5, color: C.muted, fontWeight: 600 }}>{trailing}</div>}
    </div>
  );
  const ic = {
    menu: <path d="M3 6h18M3 12h18M3 18h18" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>,
    bell: <path d="M6 9a6 6 0 1112 0c0 4 1.5 5 2 6H4c.5-1 2-2 2-6z M9.5 20a2.5 2.5 0 005 0" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    finger: <path d="M12 11v3m-4-3a4 4 0 018 0m-10 0a6 6 0 0112 0c0 3-1 5-1 5M7 14c0 2 .5 3 .5 4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" fill="none"/>,
    leave: <path d="M7 4v3m10-3v3M4 9h16M5 6h14a1 1 0 011 1v12a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1z M9 14l2 2 4-4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    task: <path d="M9 11l3 3L22 4 M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    holiday: <path d="M12 2a7 7 0 017 7c0 5-7 13-7 13S5 14 5 9a7 7 0 017-7z M12 6v6m-3-3h6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    home: <path d="M3 11l9-8 9 8M5 10v10h14V10" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    clock: <g fill="none" stroke="currentColor" strokeWidth="1.8"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2" strokeLinecap="round"/></g>,
    check: <path d="M5 13l4 4L19 7" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    chevron: <path d="M9 6l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    out: <path d="M16 17l5-5-5-5M21 12H9M9 3H5a2 2 0 00-2 2v14a2 2 0 002 2h4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" fill="none"/>,
    team: <g fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="9" cy="9" r="3"/><path d="M3.5 19c.4-2.6 2.7-4.5 5.5-4.5s5.1 1.9 5.5 4.5" strokeLinecap="round"/><path d="M16 7.5a3 3 0 010 5M17.6 19c-.2-1.6-1-3-2.3-3.9" strokeLinecap="round"/></g>,
    interview: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="4" y="3" width="16" height="18" rx="2"/><circle cx="12" cy="9" r="2.2"/><path d="M8.5 16.2c.5-1.7 2-2.6 3.5-2.6s3 .9 3.5 2.6" strokeLinecap="round"/></g>,
    payslip: <g fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M6 3h12v18l-2-1.3L14 21l-2-1.3L10 21l-2-1.3L6 21z" strokeLinejoin="round"/><path d="M9 8h6M9 11h6M9 14h4" strokeLinecap="round"/></g>,
    training: <g fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M12 4l9 4-9 4-9-4 9-4z" strokeLinejoin="round"/><path d="M7 10.5V15c0 1.4 2.2 2.5 5 2.5s5-1.1 5-2.5v-4.5M21 8.5v5" strokeLinecap="round"/></g>,
    meeting: <g fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="6" width="12" height="12" rx="2"/><path d="M15 10l6-3v10l-6-3z" strokeLinejoin="round"/></g>,
    resign: <path d="M14 3H6a2 2 0 00-2 2v14a2 2 0 002 2h8M10 12h11M18 9l3 3-3 3" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
    plus: <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"/>,
  };
  const Svg = ({ d, size = 20, color = 'currentColor' }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ color, display: 'block' }}>{d}</svg>
  );

  // ── DASHBOARD (home) ──────────────────────────────────────────────
  const StatTile = ({ label, value, color, d }) => (
    <Glass pad={14} style={{ flex: 1 }}>
      <div style={{ width: 34, height: 34, borderRadius: 10, background: color + '22', color,
        display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 10 }}><Svg d={d} size={18} /></div>
      <div style={{ fontSize: 22, fontWeight: 800, color: C.ink, letterSpacing: -0.5 }}>{value}</div>
      <div style={{ fontSize: 12, color: C.muted, fontWeight: 500, marginTop: 1 }}>{label}</div>
    </Glass>
  );
  const QuickRow = ({ d, title, desc, color, onClick }) => (
    <Glass pad={13} style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: onClick ? 'pointer' : 'default' }}>
      <div onClick={onClick} style={{ display: 'contents' }}>
      <div style={{ width: 42, height: 42, borderRadius: 12, background: color + '20', color,
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Svg d={d} size={21} /></div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 700, color: C.ink }}>{title}</div>
        <div style={{ fontSize: 12, color: C.muted, marginTop: 1 }}>{desc}</div>
      </div>
      <div style={{ color: C.muted }}><Svg d={ic.chevron} size={18} /></div>
      </div>
    </Glass>
  );
  const Dashboard = () => (
    <React.Fragment>
      <ShiftHero checkedIn={checkedIn} inTime={inTime} outTime={outTime} inEpoch={inEpoch} frozenSecs={frozenSecs} onToggle={toggleShift} C={C} />
      <div style={{ height: 16 }} />
      <div style={{ display: 'flex', gap: 10 }}>
        <StatTile label="Present days" value="18" color={success} d={ic.check} />
        <StatTile label="Hours · month" value="142h" color={info} d={ic.clock} />
      </div>
      <div style={{ height: 10 }} />
      <div style={{ display: 'flex', gap: 10 }}>
        <StatTile label="Pending leaves" value="2" color={warning} d={ic.leave} />
        <StatTile label="Active tasks" value="5" color={C.accent} d={ic.task} />
      </div>
      <div style={{ height: 22 }} />
      <SectionHead title="Quick actions" sub="Get things done in a tap" />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <QuickRow d={ic.finger} title={checkedIn ? 'Check out now' : 'Check in now'} desc={checkedIn ? 'Clock out and end your shift' : 'Open attendance to clock in'} color={C.primary} onClick={toggleShift} />
        <QuickRow d={ic.leave} title="Apply for leave" desc="Submit a new leave request" color={success} onClick={() => { setSection('leave'); setApplyOpen(true); }} />
        <QuickRow d={ic.task} title="View tasks" desc="5 active · tap to review" color={C.accent} onClick={() => setSection('task')} />
      </div>
      <div style={{ height: 22 }} />
      <SectionHead title="Today" trailing="Thu, 29 May" />
      <Glass pad={6}>
        {[['09:02','Checked in','Hyderabad HQ',success],
          ['11:30','Field visit — Kondapur','Due · In progress',warning],
          ['14:00','Submit weekly report','Due · Pending',C.accent]].map((r,i,a)=>(
          <div key={i} style={{ display: 'flex', gap: 12, padding: '12px 10px',
            borderBottom: i < a.length-1 ? '1px solid rgba(15,23,42,0.06)' : 'none' }}>
            <div style={{ fontSize: 12, fontWeight: 800, color: r[3], width: 44, paddingTop: 1 }}>{r[0]}</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: C.ink }}>{r[1]}</div>
              <div style={{ fontSize: 11.5, color: C.muted, marginTop: 1 }}>{r[2]}</div>
            </div>
          </div>
        ))}
      </Glass>
    </React.Fragment>
  );

  // ── generic list views (leave / task / attendance / holiday) ──────
  const ListView = ({ rows }) => (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {rows.map((r, i) => (
        <Glass key={i} pad={14} style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ width: 40, height: 40, borderRadius: 11, background: r.color + '20', color: r.color,
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}><Svg d={r.d} size={20} /></div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 700, color: C.ink }}>{r.title}</div>
            <div style={{ fontSize: 12, color: C.muted, marginTop: 2 }}>{r.meta}</div>
          </div>
          {r.pill && <Pill label={r.pill[0]} color={r.pill[1]} />}
        </Glass>
      ))}
    </div>
  );
  const [leaves, setLeaves] = useState([
    { d: ic.leave, color: success, title: 'Casual leave', meta: '12 Jun → 13 Jun · 2 days', pill: ['Approved', success] },
    { d: ic.leave, color: warning, title: 'Sick leave', meta: '28 May · 1 day', pill: ['Pending', warning] },
    { d: ic.leave, color: C.accent, title: 'Earned leave', meta: '02 Jul → 05 Jul · 4 days', pill: ['Pending', warning] },
  ]);
  const onApplySubmit = (r) => {
    setLeaves((prev) => [{ d: ic.leave, color: warning, title: `${r.type} leave`,
      meta: `${r.from} → ${r.to} · ${r.days} day${r.days === 1 ? '' : 's'}`, pill: ['Pending', warning] }, ...prev]);
  };
  const taskRows = [
    { d: ic.task, color: warning, title: 'Field visit — Kondapur', meta: 'Due today · In progress', pill: ['In progress', warning] },
    { d: ic.task, color: C.accent, title: 'Submit weekly report', meta: 'Due today · Pending', pill: ['Pending', info] },
    { d: ic.task, color: success, title: 'KYC verification — 4 clients', meta: 'Completed · 27 May', pill: ['Done', success] },
    { d: ic.task, color: C.primary, title: 'Beneficiary survey', meta: 'Due 31 May · Pending', pill: ['Pending', info] },
  ];
  const attRows = [
    { d: ic.check, color: success, title: 'Wed, 28 May', meta: 'In 09:01 · Out 18:12 · 9h 11m', pill: ['Present', success] },
    { d: ic.check, color: success, title: 'Tue, 27 May', meta: 'In 09:14 · Out 17:50 · 8h 36m', pill: ['Present', success] },
    { d: ic.clock, color: warning, title: 'Mon, 26 May', meta: 'In 13:30 · Out 18:00 · Half day', pill: ['Half day', warning] },
    { d: ic.leave, color: info, title: 'Fri, 23 May', meta: 'Casual leave', pill: ['On leave', info] },
  ];
  const holidayRows = [
    { d: ic.holiday, color: C.pink, title: 'Bakrid / Eid al-Adha', meta: 'Sat, 07 Jun 2025', pill: ['Upcoming', C.pink] },
    { d: ic.holiday, color: C.violet, title: 'Independence Day', meta: 'Fri, 15 Aug 2025', pill: ['Upcoming', C.violet] },
    { d: ic.holiday, color: C.accent, title: 'Gandhi Jayanti', meta: 'Thu, 02 Oct 2025', pill: ['Upcoming', C.accent] },
    { d: ic.holiday, color: warning, title: 'Diwali', meta: 'Mon, 20 Oct 2025', pill: ['Upcoming', warning] },
  ];

  const teamRows = [
    { d: ic.team, color: C.primary, title: 'Anil Kumar', meta: 'Field Manager · Reporting to', pill: ['Lead', C.primary] },
    { d: ic.team, color: success, title: 'Sana Sheikh', meta: 'Field Executive', pill: ['Active', success] },
    { d: ic.team, color: info, title: 'Ravi Teja', meta: 'Field Executive', pill: ['On leave', info] },
    { d: ic.team, color: warning, title: 'Meena Joshi', meta: 'Field Executive', pill: ['Active', success] },
    { d: ic.team, color: C.violet, title: 'Karthik N', meta: 'Field Executive', pill: ['Active', success] },
  ];
  const interviewRows = [
    { d: ic.interview, color: C.violet, title: 'Field Officer — R. Nair', meta: 'Tomorrow · 11:00 AM · Panel', pill: ['Scheduled', C.violet] },
    { d: ic.interview, color: warning, title: 'Data Entry — P. Das', meta: '02 Jun · 03:30 PM', pill: ['Scheduled', warning] },
    { d: ic.interview, color: success, title: 'Surveyor — K. Rao', meta: '24 May · Completed', pill: ['Selected', success] },
  ];
  const payslipRows = [
    { d: ic.payslip, color: success, title: 'May 2025', meta: 'Net ₹38,500 · Credited 31 May', pill: ['Paid', success] },
    { d: ic.payslip, color: success, title: 'April 2025', meta: 'Net ₹38,500 · Credited 30 Apr', pill: ['Paid', success] },
    { d: ic.payslip, color: success, title: 'March 2025', meta: 'Net ₹37,200 · Credited 31 Mar', pill: ['Paid', success] },
    { d: ic.payslip, color: success, title: 'February 2025', meta: 'Net ₹37,200 · Credited 28 Feb', pill: ['Paid', success] },
  ];
  const trainingRows = [
    { d: ic.training, color: warning, title: 'Field Safety & Compliance', meta: 'In progress · 60%', pill: ['Ongoing', warning] },
    { d: ic.training, color: success, title: 'KYC & Documentation', meta: 'Completed · 12 May', pill: ['Done', success] },
    { d: ic.training, color: info, title: 'Customer Communication', meta: 'Starts 05 Jun', pill: ['Upcoming', info] },
  ];
  const meetingRows = [
    { d: ic.meeting, color: C.primary, title: 'Weekly team sync', meta: 'Today · 05:00 PM · Google Meet', pill: ['Today', C.primary] },
    { d: ic.meeting, color: warning, title: 'Monthly review', meta: '31 May · 11:00 AM', pill: ['Upcoming', warning] },
    { d: ic.meeting, color: info, title: 'Field strategy call', meta: '02 Jun · 02:00 PM', pill: ['Upcoming', info] },
  ];

  const titles = { home: 'Dashboard', leave: 'Leaves', task: 'Tasks', attendance: 'Attendance', holiday: 'Holidays',
    team: 'My Team', interview: 'My Interview', payslips: 'My Payslips', trainings: 'My Trainings', meetings: 'My Meetings', resignation: 'Resignation' };

  const resignationView = (
    <React.Fragment>
      <SectionHead title="Resignation" sub="Submit or track your resignation" />
      <Glass pad={4} style={{ marginBottom: 14 }}>
        {[['Current status', 'Active employee', success], ['Notice period', '30 days', C.ink], ['Last working day', '—', C.muted]].map((r, i, a) => (
          <div key={i} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '13px 12px', borderBottom: i < a.length - 1 ? '1px solid rgba(15,23,42,0.06)' : 'none' }}>
            <span style={{ fontSize: 13, color: C.muted, fontWeight: 600 }}>{r[0]}</span>
            <span style={{ fontSize: 13.5, color: r[2], fontWeight: 700 }}>{r[1]}</span>
          </div>
        ))}
      </Glass>
      {resignSubmitted ? (
        <div style={{ padding: 14, borderRadius: 14, display: 'flex', alignItems: 'center', gap: 9, background: 'rgba(16,185,129,0.1)', border: '1px solid rgba(16,185,129,0.3)' }}>
          <Svg d={ic.check} size={20} color={success} />
          <span style={{ fontSize: 13, fontWeight: 600, color: '#059669' }}>Resignation request submitted to HR for review.</span>
        </div>
      ) : (
        <button onClick={() => setResignSubmitted(true)} style={{ width: '100%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, padding: '15px', borderRadius: 13, background: danger + '12', border: '1px solid ' + danger + '40', color: danger, fontFamily: 'Roboto, system-ui', fontSize: 14.5, fontWeight: 700 }}>
          <Svg d={ic.resign} size={18} />Apply for resignation
        </button>
      )}
      <div style={{ fontSize: 12, color: C.muted, textAlign: 'center', marginTop: 14, lineHeight: 1.4 }}>Your manager and HR will be notified once you submit.</div>
    </React.Fragment>
  );

  const listSection = (title, sub, trailing, rows) => <React.Fragment><SectionHead title={title} sub={sub} trailing={trailing} /><ListView rows={rows} /></React.Fragment>;

  const body = section === 'home' ? Dashboard()
    : section === 'leave' ? <React.Fragment>
        <button onClick={() => setApplyOpen(true)} style={{ width: '100%', marginBottom: 16, cursor: 'pointer', border: 'none',
          padding: '14px', borderRadius: 14, color: '#fff', fontFamily: 'Roboto, system-ui', fontSize: 14.5, fontWeight: 700,
          letterSpacing: 0.2, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          background: 'linear-gradient(135deg,#4F46E5 0%,#06B6D4 100%)', boxShadow: '0 12px 26px rgba(79,70,229,0.34)' }}>
          <Svg d={ic.plus} size={19} color="#fff" />Apply for leave
        </button>
        <SectionHead title="Your leaves" trailing={`${leaves.filter(l => l.pill[0] === 'Pending').length} pending`} />
        <ListView rows={leaves} />
      </React.Fragment>
    : section === 'task' ? listSection('Your tasks', null, '5 active', taskRows)
    : section === 'attendance' ? listSection('Attendance', 'This month', null, attRows)
    : section === 'holiday' ? listSection('Holidays', '2025 calendar', null, holidayRows)
    : section === 'team' ? listSection('My team', '5 members', null, teamRows)
    : section === 'interview' ? listSection('My interviews', 'Panels you’re on', null, interviewRows)
    : section === 'payslips' ? listSection('My payslips', 'Recent months', null, payslipRows)
    : section === 'trainings' ? listSection('My trainings', 'Assigned to you', null, trainingRows)
    : section === 'meetings' ? listSection('My meetings', 'Upcoming', null, meetingRows)
    : resignationView;

  // ── bottom nav ────────────────────────────────────────────────────
  const bottomTabs = [['home','Home',ic.home],['leave','Leave',ic.leave],['task','Task',ic.task]];
  const menuMain = [['attendance','Attendance',ic.finger,C.accent],['leave','Leave',ic.leave,success],['task','Task',ic.task,warning],['holiday','Holiday',ic.holiday,C.pink]];
  const menuMore = [['team','My Team',ic.team,info],['interview','My Interview',ic.interview,C.violet],['payslips','My Payslips',ic.payslip,success],['trainings','My Trainings',ic.training,C.accent],['meetings','My Meetings',ic.meeting,C.primary],['resignation','Resignation',ic.resign,danger]];

  const go = (s) => { setSection(s); setDrawer(false); };
  const menuItem = ([key, label, d, color]) => {
    const on = section === key;
    return (
      <button key={key} onClick={() => go(key)} style={{ width: '100%', textAlign: 'left', cursor: 'pointer', marginBottom: 4,
        display: 'flex', alignItems: 'center', gap: 12, padding: '11px 10px', borderRadius: 12,
        border: '1px solid ' + (on ? color + '47' : 'transparent'),
        background: on ? `linear-gradient(90deg,${color}22,${color}0a)` : 'transparent' }}>
        <span style={{ width: 4, height: 22, borderRadius: 2, background: on ? color : 'transparent' }} />
        <span style={{ width: 32, height: 32, borderRadius: 9, display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: on ? color : C.muted, background: on ? color + '26' : 'rgba(255,255,255,0.5)',
          border: '1px solid ' + (on ? color + '47' : 'rgba(255,255,255,0.6)') }}><Svg d={d} size={17} /></span>
        <span style={{ flex: 1, fontSize: 13.5, fontWeight: on ? 700 : 600, color: on ? color : C.inkSoft }}>{label}</span>
      </button>
    );
  };

  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui', overflow: 'hidden' }}>
      {Mesh ? <Mesh intensity={0.8} /> : <div style={{ position: 'absolute', inset: 0, background: '#EEF1F8' }} />}

      {/* scrollable body */}
      <div style={{ position: 'absolute', inset: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch',
        padding: '112px 16px 96px' }}>
        {body}
      </div>

      {/* app bar */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 30,
        paddingTop: 50, background: 'rgba(255,255,255,0.62)',
        backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)',
        borderBottom: '1px solid rgba(255,255,255,0.55)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 12px 10px' }}>
          <button onClick={() => setDrawer(true)} style={{ width: 38, height: 38, borderRadius: 11, cursor: 'pointer',
            background: 'rgba(255,255,255,0.6)', border: '1px solid rgba(255,255,255,0.6)', color: C.inkSoft,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Svg d={ic.menu} size={18} /></button>
          <Avatar size={36} radius={11} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 15.5, fontWeight: 700, color: C.ink, letterSpacing: -0.1 }}>{titles[section]}</div>
            <div style={{ fontSize: 11.5, color: C.muted, fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</div>
          </div>
          <button style={{ width: 38, height: 38, borderRadius: 11, cursor: 'pointer', position: 'relative',
            background: 'rgba(255,255,255,0.6)', border: '1px solid rgba(255,255,255,0.6)', color: C.inkSoft,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Svg d={ic.bell} size={19} />
            <span style={{ position: 'absolute', top: 8, right: 9, width: 7, height: 7, borderRadius: '50%', background: danger, border: '1.5px solid #fff' }} />
          </button>
        </div>
      </div>

      {/* bottom nav */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 30,
        paddingBottom: 22, background: 'rgba(255,255,255,0.62)',
        backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)',
        borderTop: '1px solid rgba(255,255,255,0.55)', boxShadow: '0 -4px 16px rgba(16,24,40,0.05)' }}>
        <div style={{ display: 'flex', padding: '8px 8px 4px' }}>
          {bottomTabs.map(([key, label, d]) => {
            const on = section === key;
            return (
              <button key={key} onClick={() => setSection(key)} style={{ flex: 1, background: 'none', border: 'none', cursor: 'pointer',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, padding: '4px 0', color: on ? C.primary : C.muted }}>
                <div style={{ padding: '4px 16px', borderRadius: 999, background: on ? C.primary + '1f' : 'transparent', transition: 'background .2s' }}>
                  <Svg d={d} size={22} />
                </div>
                <span style={{ fontSize: 11, fontWeight: 700 }}>{label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* drawer scrim */}
      <div onClick={() => setDrawer(false)} style={{ position: 'absolute', inset: 0, zIndex: 40,
        background: 'rgba(15,23,42,0.40)', opacity: drawer ? 1 : 0, pointerEvents: drawer ? 'auto' : 'none',
        transition: 'opacity .3s ease' }} />

      {/* left navigation drawer */}
      <div style={{ position: 'absolute', top: 0, bottom: 0, left: 0, width: 296, zIndex: 50,
        transform: `translateX(${drawer ? 0 : -100}%)`, transition: 'transform .34s cubic-bezier(.4,0,.2,1)',
        background: 'rgba(255,255,255,0.78)', backdropFilter: 'blur(26px)', WebkitBackdropFilter: 'blur(26px)',
        borderRight: '1px solid rgba(255,255,255,0.6)', boxShadow: '14px 0 40px rgba(15,23,42,0.18)',
        display: 'flex', flexDirection: 'column' }}>
        {/* profile header */}
        <button onClick={() => { setProfileOpen(true); setDrawer(false); }} style={{ display: 'block', width: '100%', textAlign: 'left', border: 'none', cursor: 'pointer', padding: '62px 18px 18px', background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 60%,#06B6D4 140%)', color: '#fff', position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', width: 160, height: 160, borderRadius: '50%', top: -60, right: -40, background: 'radial-gradient(circle,rgba(255,255,255,0.16),transparent 70%)' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 13, position: 'relative' }}>
            <div style={{ width: 54, height: 54, borderRadius: 16, background: 'rgba(255,255,255,0.22)', border: '1.5px solid rgba(255,255,255,0.5)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, fontSize: 19 }}>{initials}</div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div style={{ fontSize: 17, fontWeight: 800, letterSpacing: -0.2, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</div>
              <div style={{ fontSize: 12.5, opacity: 0.9, marginTop: 1 }}>{role}</div>
            </div>
            <span style={{ opacity: 0.9 }}><Svg d={ic.chevron} size={18} color="#fff" /></span>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14, position: 'relative' }}>
            <span style={{ padding: '4px 10px', borderRadius: 999, fontSize: 11, fontWeight: 700, background: 'rgba(255,255,255,0.18)', border: '1px solid rgba(255,255,255,0.3)' }}>ID · {empId}</span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 10px', borderRadius: 999, fontSize: 11, fontWeight: 700, background: 'rgba(255,255,255,0.18)', border: '1px solid rgba(255,255,255,0.3)' }}>
              <span style={{ width: 7, height: 7, borderRadius: '50%', background: '#34D399' }} />Active
            </span>
          </div>
        </button>

        {/* menu */}
        <div style={{ flex: 1, minHeight: 0, overflowY: 'auto', WebkitOverflowScrolling: 'touch', padding: '12px 12px' }}>
          <div style={{ fontSize: 10, fontWeight: 800, letterSpacing: 1.4, color: C.muted, padding: '6px 10px 8px' }}>MENU</div>
          {menuMain.map(menuItem)}
          <div style={{ fontSize: 10, fontWeight: 800, letterSpacing: 1.4, color: C.muted, padding: '14px 10px 8px' }}>WORKPLACE</div>
          {menuMore.map(menuItem)}
        </div>

        {/* footer links */}
        <div style={{ padding: '8px 12px 2px', borderTop: '1px solid rgba(15,23,42,0.07)' }}>
          {[['Notifications', ic.bell, danger], ['Privacy & security', <path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6l7-3z M9.5 12l1.8 1.8L15 10" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>, null]].map(([label, d, badge]) => (
            <button key={label} onClick={() => setDrawer(false)} style={{ width: '100%', textAlign: 'left', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 12, padding: '10px 10px', borderRadius: 11, border: 'none', background: 'transparent' }}>
              <span style={{ width: 32, height: 32, borderRadius: 9, display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: C.muted, background: 'rgba(255,255,255,0.5)', border: '1px solid rgba(255,255,255,0.6)' }}><Svg d={d} size={17} /></span>
              <span style={{ flex: 1, fontSize: 13.5, fontWeight: 600, color: C.inkSoft }}>{label}</span>
              {badge && <span style={{ minWidth: 18, height: 18, padding: '0 5px', borderRadius: 999, background: badge, color: '#fff', fontSize: 10.5, fontWeight: 800, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>3</span>}
              <span style={{ color: C.muted }}><Svg d={ic.chevron} size={15} /></span>
            </button>
          ))}
        </div>

        {/* sign out */}
        <div style={{ padding: '8px 16px 10px', borderTop: '1px solid rgba(15,23,42,0.07)' }}>
          <button onClick={onSignOut} style={{ width: '100%', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 10,
            padding: '12px 12px', borderRadius: 12, background: danger + '12', border: '1px solid ' + danger + '33', color: danger,
            fontFamily: 'Roboto, system-ui', fontSize: 13.5, fontWeight: 700 }}>
            <Svg d={ic.out} size={18} />Sign out
          </button>
        </div>
      </div>

      {/* apply-for-leave sheet */}
      <ApplyLeaveSheet open={applyOpen} onClose={() => setApplyOpen(false)} onSubmit={onApplySubmit} />

      {/* employee profile */}
      <EmployeeProfile open={profileOpen} onBack={() => setProfileOpen(false)} name={name} initials={initials} role={role} empId={empId} onSignOut={onSignOut} />
    </div>
  );
}

window.HomeScreen = HomeScreen;
