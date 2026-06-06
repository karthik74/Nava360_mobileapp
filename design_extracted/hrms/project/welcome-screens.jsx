// Welcome-screen variations for Nava360 HRMS.
// Built on the app's glass-morphism design tokens (lib/core/theme.dart).
// Exports screen components to window for the canvas to mount.

const C = {
  primary: '#4F46E5',
  primaryDark: '#3730A3',
  accent: '#06B6D4',
  pink: '#EC4899',
  violet: '#8B5CF6',
  ink: '#0F172A',
  inkSoft: '#334155',
  muted: '#64748B',
  teal: '#14B8A6',
  green: '#10B981',
};
const LOGO = 'assets/logo-mark.png';

// ── Shared: the colourful mesh canvas behind glass (mirrors GlassBackdrop) ──
function Mesh({ intensity = 1, veil = true, children, style = {} }) {
  const blob = (s, c, pos) => (
    <div style={{
      position: 'absolute', width: s, height: s, borderRadius: '50%',
      background: `radial-gradient(circle, ${c} 0%, rgba(0,0,0,0) 70%)`,
      ...pos,
    }} />
  );
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden',
      background: 'linear-gradient(135deg,#EDF1FB 0%,#F4ECFB 50%,#E8F4FB 100%)', ...style }}>
      {blob(360, `rgba(99,102,241,${0.32*intensity})`, { top: -120, left: -100 })}
      {blob(320, `rgba(6,182,212,${0.28*intensity})`, { top: -60, right: -120 })}
      {blob(380, `rgba(236,72,153,${0.24*intensity})`, { bottom: -170, left: -50 })}
      {blob(280, `rgba(139,92,246,${0.24*intensity})`, { bottom: 80, right: -110 })}
      {veil && <div style={{ position: 'absolute', inset: 0,
        background: 'linear-gradient(to bottom,rgba(255,255,255,0.30),rgba(255,255,255,0.12) 50%,rgba(255,255,255,0.25))' }} />}
      {children}
    </div>
  );
}

// ── Shared: primary gradient CTA (mirrors _GradientButton from login) ──
function PrimaryCTA({ label = 'Get Started', onClick, style = {} }) {
  const [hover, setHover] = React.useState(false);
  return (
    <button onClick={onClick}
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        width: '100%', border: 'none', cursor: 'pointer',
        padding: '17px 18px', borderRadius: 14,
        background: 'linear-gradient(135deg,#4F46E5 0%,#06B6D4 100%)',
        color: '#fff', fontFamily: 'Roboto, system-ui', fontSize: 16, fontWeight: 700, whiteSpace: 'nowrap',
        letterSpacing: 0.3, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        boxShadow: hover ? '0 14px 34px rgba(79,70,229,0.50)' : '0 10px 26px rgba(79,70,229,0.40)',
        transform: hover ? 'translateY(-1px)' : 'none', transition: 'all .2s ease', ...style,
      }}>
      {label}
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
        <path d="M5 12h14M13 6l6 6-6 6" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </button>
  );
}

function SignInLink({ style = {}, onClick }) {
  return (
    <div style={{ textAlign: 'center', fontFamily: 'Roboto, system-ui', fontSize: 14,
      color: C.muted, fontWeight: 500, ...style }}>
      Already have an account?{' '}
      <span onClick={onClick} style={{ color: C.primary, fontWeight: 700, cursor: 'pointer' }}>Sign in</span>
    </div>
  );
}

// little dot+label feature pill
function FeatPill({ color, label }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '8px 14px',
      borderRadius: 999, background: 'rgba(255,255,255,0.55)',
      border: '1px solid rgba(255,255,255,0.7)', backdropFilter: 'blur(8px)',
      boxShadow: '0 2px 8px rgba(16,24,40,0.05)' }}>
      <span style={{ width: 8, height: 8, borderRadius: '50%', background: color }} />
      <span style={{ fontFamily: 'Roboto, system-ui', fontSize: 13, fontWeight: 700, color: C.inkSoft }}>{label}</span>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// A · Hero band — by-the-book, matches the existing login screen
// ════════════════════════════════════════════════════════════════════
function WelcomeA({ onStart }) {
  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui' }}>
      <Mesh veil={true} />
      {/* hero gradient band */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '47%',
        background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 45%,#06B6D4 130%)',
        borderBottomLeftRadius: 36, borderBottomRightRadius: 36, overflow: 'hidden' }}>
        <div style={{ position: 'absolute', inset: 0,
          background: 'linear-gradient(225deg,rgba(255,255,255,0.18),transparent 55%,rgba(0,0,0,0.06))' }} />
        <div style={{ position: 'absolute', width: 240, height: 240, borderRadius: '50%',
          top: -70, right: -60, background: 'radial-gradient(circle,rgba(255,255,255,0.18),transparent 70%)' }} />
        <div style={{ position: 'absolute', width: 200, height: 200, borderRadius: '50%',
          bottom: -50, left: -40, background: 'radial-gradient(circle,rgba(6,182,212,0.5),transparent 70%)' }} />
      </div>

      {/* hero content */}
      <div style={{ position: 'absolute', top: 96, left: 28, right: 28 }}>
        <div style={{ width: 92, height: 92, borderRadius: 26, background: 'rgba(255,255,255,0.95)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 14px 30px rgba(15,23,42,0.22)', border: '1px solid rgba(255,255,255,0.8)' }}>
          <img src={LOGO} alt="Nava360" style={{ width: 76, height: 76, objectFit: 'contain' }} />
        </div>
        <div style={{ marginTop: 26, color: '#fff', fontSize: 15, fontWeight: 600,
          letterSpacing: 2, opacity: 0.85 }}>WELCOME TO</div>
        <div style={{ color: '#fff', fontSize: 42, fontWeight: 800, letterSpacing: -0.5, lineHeight: 1.05, marginTop: 4 }}>Nava360</div>
        <div style={{ color: 'rgba(255,255,255,0.88)', fontSize: 16, marginTop: 12, lineHeight: 1.45, maxWidth: 300 }}>
          Your whole workforce — attendance, tasks and teams — wherever the work takes you.
        </div>
      </div>

      {/* glass action card */}
      <div style={{ position: 'absolute', left: 20, right: 20, bottom: 30,
        borderRadius: 24, padding: 22, background: 'rgba(255,255,255,0.62)',
        backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
        border: '1px solid rgba(255,255,255,0.7)',
        boxShadow: '0 18px 40px rgba(99,102,241,0.18),0 2px 6px rgba(15,23,42,0.06)' }}>
        <div style={{ display: 'flex', gap: 8, marginBottom: 18, flexWrap: 'wrap' }}>
          <FeatPill color={C.green} label="Attendance" />
          <FeatPill color={C.primary} label="Tasks" />
          <FeatPill color={C.accent} label="Leave" />
        </div>
        <PrimaryCTA label="Get Started" onClick={onStart} />
        <SignInLink style={{ marginTop: 16 }} onClick={onStart} />
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// B · Centered glass orb — logo-forward, airy
// ════════════════════════════════════════════════════════════════════
function WelcomeB({ onStart }) {
  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui' }}>
      <Mesh intensity={1.1} />
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', padding: '0 32px', paddingTop: 40 }}>
        {/* frosted orb holding the logo */}
        <div style={{ position: 'relative', width: 176, height: 176, marginBottom: 38 }}>
          <div style={{ position: 'absolute', inset: -14, borderRadius: '50%',
            background: 'radial-gradient(circle,rgba(99,102,241,0.22),transparent 70%)' }} />
          <div style={{ position: 'absolute', inset: 0, borderRadius: '50%',
            background: 'rgba(255,255,255,0.55)', backdropFilter: 'blur(18px)', WebkitBackdropFilter: 'blur(18px)',
            border: '1.5px solid rgba(255,255,255,0.8)',
            boxShadow: '0 22px 50px rgba(99,102,241,0.22),inset 0 2px 8px rgba(255,255,255,0.6)',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <img src={LOGO} alt="Nava360" style={{ width: 124, height: 124, objectFit: 'contain' }} />
          </div>
        </div>

        <div style={{ fontSize: 40, fontWeight: 800, letterSpacing: -0.5, color: C.ink }}>Nava360</div>
        <div style={{ fontSize: 16.5, color: C.muted, marginTop: 12, textAlign: 'center', lineHeight: 1.5, maxWidth: 290, textWrap: 'pretty' }}>
          The complete HRMS for field teams — clock in, complete tasks and manage leave from anywhere.
        </div>

        <div style={{ display: 'flex', gap: 9, marginTop: 26 }}>
          <FeatPill color={C.green} label="Attendance" />
          <FeatPill color={C.primary} label="Tasks" />
          <FeatPill color={C.accent} label="Leave" />
        </div>
      </div>

      {/* pinned bottom actions */}
      <div style={{ position: 'absolute', left: 24, right: 24, bottom: 34 }}>
        <PrimaryCTA label="Get Started" onClick={onStart} />
        <SignInLink style={{ marginTop: 18 }} onClick={onStart} />
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// C · Bold layered, teal-led — field-energetic
// ════════════════════════════════════════════════════════════════════
function WelcomeC({ onStart }) {
  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui',
      background: 'linear-gradient(160deg,#06B6D4 0%,#0E7490 38%,#3730A3 100%)', overflow: 'hidden' }}>
      {/* layered glow + giant watermark logo */}
      <div style={{ position: 'absolute', width: 300, height: 300, borderRadius: '50%', top: -90, right: -90,
        background: 'radial-gradient(circle,rgba(20,184,166,0.55),transparent 70%)' }} />
      <div style={{ position: 'absolute', width: 260, height: 260, borderRadius: '50%', bottom: -60, left: -80,
        background: 'radial-gradient(circle,rgba(79,70,229,0.6),transparent 70%)' }} />
      <img src={LOGO} alt="" style={{ position: 'absolute', width: 460, height: 460, right: -150, top: 150,
        opacity: 0.10, filter: 'brightness(0) invert(1)', pointerEvents: 'none' }} />

      {/* top brand row */}
      <div style={{ position: 'absolute', top: 92, left: 28, right: 28, display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ width: 52, height: 52, borderRadius: 16, background: 'rgba(255,255,255,0.95)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 8px 20px rgba(0,0,0,0.25)' }}>
          <img src={LOGO} alt="Nava360" style={{ width: 42, height: 42, objectFit: 'contain' }} />
        </div>
        <span style={{ color: '#fff', fontSize: 22, fontWeight: 800, letterSpacing: -0.3 }}>Nava360</span>
      </div>

      {/* hero headline */}
      <div style={{ position: 'absolute', left: 28, right: 28, top: 238 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '7px 13px', borderRadius: 999,
          background: 'rgba(255,255,255,0.16)', border: '1px solid rgba(255,255,255,0.3)', marginBottom: 18 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: '#34D399', boxShadow: '0 0 8px #34D399' }} />
          <span style={{ color: '#fff', fontSize: 12.5, fontWeight: 700, letterSpacing: 0.4 }}>BY NAVACHETANA LIVELIHOODS</span>
        </div>
        <div style={{ color: '#fff', fontSize: 44, fontWeight: 800, lineHeight: 1.04, letterSpacing: -0.8 }}>
          Field work,<br/>fully handled.
        </div>
        <div style={{ color: 'rgba(255,255,255,0.85)', fontSize: 16, marginTop: 16, lineHeight: 1.5, maxWidth: 310 }}>
          Track attendance with GPS, complete field tasks and request leave — all from one app built for the ground.
        </div>
      </div>

      {/* bottom glass action sheet */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: '22px 22px 44px',
        borderTopLeftRadius: 30, borderTopRightRadius: 30,
        background: 'rgba(255,255,255,0.16)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderTop: '1px solid rgba(255,255,255,0.3)' }}>
        <div style={{ display: 'flex', gap: 18, marginBottom: 18, justifyContent: 'space-between' }}>
          {[['Attendance','#34D399'],['Tasks','#fff'],['Leave','#A5F3FC'],['Team','#C4B5FD']].map(([t,c]) => (
            <div key={t} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 9, height: 9, borderRadius: '50%', background: c }} />
              <span style={{ color: 'rgba(255,255,255,0.9)', fontSize: 12, fontWeight: 700 }}>{t}</span>
            </div>
          ))}
        </div>
        <button onClick={onStart} style={{ width: '100%', border: 'none', cursor: 'pointer', padding: '16px', borderRadius: 14,
          background: '#fff', color: C.primaryDark, fontFamily: 'Roboto, system-ui', fontSize: 16, fontWeight: 800, whiteSpace: 'nowrap',
          letterSpacing: 0.3, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          boxShadow: '0 12px 30px rgba(0,0,0,0.25)' }}>
          Get Started
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <path d="M5 12h14M13 6l6 6-6 6" stroke={C.primaryDark} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
        <div style={{ textAlign: 'center', marginTop: 16, color: 'rgba(255,255,255,0.8)', fontSize: 14, fontWeight: 500 }}>
          Already have an account? <span onClick={onStart} style={{ color: '#fff', fontWeight: 800, cursor: 'pointer' }}>Sign in</span>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Login screen — mirrors lib/features/auth/login_screen.dart
// ════════════════════════════════════════════════════════════════════
function LoginField({ icon, type = 'text', placeholder, value, onChange, suffix, focused, onFocus, onBlur }) {
  return (
    <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
      <div style={{ position: 'absolute', left: 13, display: 'flex', color: C.muted, pointerEvents: 'none' }}>{icon}</div>
      <input
        type={type} value={value} placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)} onFocus={onFocus} onBlur={onBlur}
        style={{
          width: '100%', boxSizing: 'border-box', padding: '13px 44px 13px 42px',
          borderRadius: 12, fontFamily: 'Roboto, system-ui', fontSize: 14, color: C.ink,
          background: 'rgba(255,255,255,0.7)', outline: 'none',
          border: focused ? '1.6px solid #4F46E5' : '1px solid rgba(255,255,255,0.85)',
          boxShadow: focused ? '0 0 0 3px rgba(79,70,229,0.12)' : 'none', transition: 'all .15s ease',
        }} />
      {suffix && <div style={{ position: 'absolute', right: 8 }}>{suffix}</div>}
    </div>
  );
}

function LoginScreen({ onBack, onForgot, flash, onSignedIn }) {
  const { useState } = React;
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [obscure, setObscure] = useState(true);
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [err, setErr] = useState(null);
  const [focus, setFocus] = useState(null);

  const submit = () => {
    if (!user.trim() || !pass) { setErr('Please enter your username and password.'); return; }
    setErr(null); setLoading(true);
    setTimeout(() => { setLoading(false); setDone(true); setTimeout(() => onSignedIn && onSignedIn(user), 550); }, 1400);
  };

  const label = (t) => (
    <div style={{ fontSize: 13, fontWeight: 600, color: C.ink, letterSpacing: 0.1, marginBottom: 8 }}>{t}</div>
  );

  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui', overflow: 'hidden' }}>
      <Mesh veil={false} />
      {/* hero gradient band */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '42%',
        background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 50%,#06B6D4 130%)', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', inset: 0,
          background: 'linear-gradient(225deg,rgba(255,255,255,0.18),transparent 52%,rgba(0,0,0,0.04))' }} />
        <div style={{ position: 'absolute', width: 220, height: 220, borderRadius: '50%', top: -60, right: -50,
          background: 'radial-gradient(circle,rgba(6,182,212,0.45),transparent 70%)' }} />
      </div>

      {/* back button */}
      <button onClick={onBack} style={{ position: 'absolute', top: 58, left: 18, zIndex: 5,
        width: 40, height: 40, borderRadius: 999, border: '1px solid rgba(255,255,255,0.35)', cursor: 'pointer',
        background: 'rgba(255,255,255,0.18)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="11" height="18" viewBox="0 0 12 20" fill="none">
          <path d="M10 2L2 10l8 8" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </button>

      {/* header */}
      <div style={{ position: 'absolute', top: 112, left: 28, right: 28 }}>
        <div style={{ width: 64, height: 64, borderRadius: 20, background: 'rgba(255,255,255,0.95)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 12px 26px rgba(15,23,42,0.22)', border: '1px solid rgba(255,255,255,0.8)' }}>
          <img src={LOGO} alt="Nava360" style={{ width: 52, height: 52, objectFit: 'contain' }} />
        </div>
        <div style={{ marginTop: 18, color: '#fff', fontSize: 30, fontWeight: 800, letterSpacing: 0 }}>Welcome back</div>
        <div style={{ color: 'rgba(255,255,255,0.85)', fontSize: 15, marginTop: 6 }}>Sign in to access your workspace</div>
      </div>

      {/* glass form card */}
      <div style={{ position: 'absolute', top: 286, left: 20, right: 20,
        borderRadius: 20, padding: 22, background: 'rgba(255,255,255,0.62)',
        backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
        border: '1px solid rgba(255,255,255,0.7)',
        boxShadow: '0 22px 48px rgba(99,102,241,0.22),0 2px 6px rgba(15,23,42,0.06)' }}>
        {flash && (
          <div style={{ marginBottom: 16, padding: 12, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8,
            background: 'rgba(16,185,129,0.10)', border: '1px solid rgba(16,185,129,0.30)' }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="#10B981" strokeWidth="1.8"/><path d="M8 12.5l2.5 2.5L16 9.5" stroke="#10B981" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/></svg>
            <span style={{ color: '#059669', fontSize: 12.8, fontWeight: 600 }}>{flash}</span>
          </div>
        )}
        {label('Username')}
        <LoginField
          placeholder="Enter your username" value={user} onChange={setUser}
          focused={focus === 'u'} onFocus={() => setFocus('u')} onBlur={() => setFocus(null)}
          icon={<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="8" r="4" stroke="currentColor" strokeWidth="1.8"/><path d="M4 20c0-3.3 3.6-6 8-6s8 2.7 8 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/></svg>} />
        <div style={{ height: 16 }} />
        {label('Password')}
        <LoginField
          type={obscure ? 'password' : 'text'} placeholder="••••••••" value={pass} onChange={setPass}
          focused={focus === 'p'} onFocus={() => setFocus('p')} onBlur={() => setFocus(null)}
          icon={<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="4" y="10" width="16" height="10" rx="2.5" stroke="currentColor" strokeWidth="1.8"/><path d="M8 10V7a4 4 0 018 0v3" stroke="currentColor" strokeWidth="1.8"/></svg>}
          suffix={
            <button onClick={() => setObscure(!obscure)} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: C.muted, display: 'flex' }}>
              {obscure
                ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" stroke="currentColor" strokeWidth="1.7"/><circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.7"/></svg>
                : <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" stroke="currentColor" strokeWidth="1.7"/><circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.7"/><path d="M3 3l18 18" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>}
            </button>
          } />

        {/* forgot password */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 10 }}>
          <span onClick={onForgot}
            style={{ fontSize: 13, fontWeight: 600, color: C.primary, cursor: 'pointer' }}>Forgot password?</span>
        </div>

        {err && (
          <div style={{ marginTop: 16, padding: 12, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8,
            background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.25)' }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="#EF4444" strokeWidth="1.8"/><path d="M12 7v6M12 16.5v.5" stroke="#EF4444" strokeWidth="1.8" strokeLinecap="round"/></svg>
            <span style={{ color: '#EF4444', fontSize: 13, fontWeight: 500 }}>{err}</span>
          </div>
        )}

        <div style={{ marginTop: err ? 16 : 22 }} />
        <button onClick={submit} disabled={loading || done}
          style={{ width: '100%', border: 'none', cursor: loading ? 'default' : 'pointer', padding: '16px', borderRadius: 12,
            background: done ? 'linear-gradient(135deg,#10B981,#34D399)' : 'linear-gradient(135deg,#4F46E5 0%,#06B6D4 100%)',
            color: '#fff', fontFamily: 'Roboto, system-ui', fontSize: 15, fontWeight: 700, letterSpacing: 0.3,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            boxShadow: '0 12px 28px rgba(79,70,229,0.40)', transition: 'background .3s ease' }}>
          {loading
            ? <span style={{ width: 20, height: 20, border: '2.4px solid rgba(255,255,255,0.4)', borderTopColor: '#fff', borderRadius: '50%', display: 'inline-block', animation: 'navaspin 0.7s linear infinite' }} />
            : done
              ? <React.Fragment><svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 13l4 4L19 7" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/></svg>Signed in</React.Fragment>
              : <React.Fragment>Sign in<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 12h14M13 6l6 6-6 6" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/></svg></React.Fragment>}
        </button>
      </div>

      <div style={{ position: 'absolute', bottom: 22, left: 0, right: 0, textAlign: 'center',
        color: C.muted, fontSize: 12, fontWeight: 500 }}>Secured by HRMS · v1.0</div>
    </div>
  );
}

// ── Shared auth-page chrome (hero band + back + header + glass card) ──
// Header and card are in normal flow so the card always sits BELOW the
// subtitle no matter how many lines it wraps to (never overlaps).
function AuthShell({ title, subtitle, onBack, children }) {
  return (
    <div style={{ position: 'absolute', inset: 0, fontFamily: 'Roboto, system-ui', overflow: 'hidden' }}>
      <Mesh veil={false} />
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: '38%',
        background: 'linear-gradient(135deg,#4F46E5 0%,#3730A3 50%,#06B6D4 130%)', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', inset: 0,
          background: 'linear-gradient(225deg,rgba(255,255,255,0.18),transparent 52%,rgba(0,0,0,0.04))' }} />
        <div style={{ position: 'absolute', width: 220, height: 220, borderRadius: '50%', top: -60, right: -50,
          background: 'radial-gradient(circle,rgba(6,182,212,0.45),transparent 70%)' }} />
      </div>
      <button onClick={onBack} style={{ position: 'absolute', top: 58, left: 18, zIndex: 5,
        width: 40, height: 40, borderRadius: 999, border: '1px solid rgba(255,255,255,0.35)', cursor: 'pointer',
        background: 'rgba(255,255,255,0.18)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="11" height="18" viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10l8 8" stroke="#fff" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
      </button>
      <div style={{ position: 'relative', zIndex: 2, height: '100%', boxSizing: 'border-box',
        overflowY: 'auto', padding: '104px 20px 28px' }}>
        <div style={{ padding: '0 8px' }}>
          <div style={{ width: 60, height: 60, borderRadius: 18, background: 'rgba(255,255,255,0.95)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '0 12px 26px rgba(15,23,42,0.22)', border: '1px solid rgba(255,255,255,0.8)' }}>
            <img src={LOGO} alt="Nava360" style={{ width: 48, height: 48, objectFit: 'contain' }} />
          </div>
          <div style={{ marginTop: 16, color: '#fff', fontSize: 26, fontWeight: 800 }}>{title}</div>
          <div style={{ color: 'rgba(255,255,255,0.9)', fontSize: 14.5, marginTop: 6, lineHeight: 1.4 }}>{subtitle}</div>
        </div>
        <div style={{ height: 22 }} />
        <div style={{ borderRadius: 20, padding: 22, background: 'rgba(255,255,255,0.62)',
          backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
          border: '1px solid rgba(255,255,255,0.7)',
          boxShadow: '0 22px 48px rgba(99,102,241,0.22),0 2px 6px rgba(15,23,42,0.06)' }}>
          {children}
        </div>
      </div>
    </div>
  );
}

const fieldLabel = (t) => <div style={{ fontSize: 13, fontWeight: 600, color: C.ink, marginBottom: 8 }}>{t}</div>;
const eyeToggle = (on, set) => (
  <button onClick={() => set(!on)} style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: C.muted, display: 'flex' }}>
    {on
      ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" stroke="currentColor" strokeWidth="1.7"/><circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.7"/></svg>
      : <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z" stroke="currentColor" strokeWidth="1.7"/><circle cx="12" cy="12" r="3" stroke="currentColor" strokeWidth="1.7"/><path d="M3 3l18 18" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>}
  </button>
);

function ErrBox({ msg }) {
  return (
    <div style={{ marginTop: 16, padding: 12, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 8,
      background: 'rgba(239,68,68,0.08)', border: '1px solid rgba(239,68,68,0.25)' }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" stroke="#EF4444" strokeWidth="1.8"/><path d="M12 7v6M12 16.5v.5" stroke="#EF4444" strokeWidth="1.8" strokeLinecap="round"/></svg>
      <span style={{ color: '#EF4444', fontSize: 13, fontWeight: 500 }}>{msg}</span>
    </div>
  );
}

function AuthBtn({ label, onClick, loading, ok }) {
  return (
    <button onClick={onClick} disabled={loading || ok}
      style={{ width: '100%', border: 'none', cursor: loading ? 'default' : 'pointer', padding: '16px', borderRadius: 12,
        background: ok ? 'linear-gradient(135deg,#10B981,#34D399)' : 'linear-gradient(135deg,#4F46E5 0%,#06B6D4 100%)',
        color: '#fff', fontFamily: 'Roboto, system-ui', fontSize: 15, fontWeight: 700, letterSpacing: 0.3,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        boxShadow: '0 12px 28px rgba(79,70,229,0.40)', transition: 'background .3s ease' }}>
      {loading
        ? <span style={{ width: 20, height: 20, border: '2.4px solid rgba(255,255,255,0.4)', borderTopColor: '#fff', borderRadius: '50%', display: 'inline-block', animation: 'navaspin 0.7s linear infinite' }} />
        : ok
          ? <React.Fragment><svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 13l4 4L19 7" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/></svg>Done</React.Fragment>
          : <React.Fragment>{label}<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><path d="M5 12h14M13 6l6 6-6 6" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/></svg></React.Fragment>}
    </button>
  );
}

// ── 4-digit OTP boxes with auto-advance ──
function OtpInput({ value, onChange, len = 4 }) {
  const refs = React.useRef([]);
  const set = (i, v) => {
    v = (v || '').replace(/\D/g, '').slice(-1);
    const arr = value.padEnd(len, ' ').split('');
    arr[i] = v || ' ';
    onChange(arr.join('').replace(/ /g, '').slice(0, len));
    if (v && i < len - 1 && refs.current[i + 1]) refs.current[i + 1].focus();
  };
  const onKey = (i, e) => {
    if (e.key === 'Backspace' && !value[i] && i > 0 && refs.current[i - 1]) refs.current[i - 1].focus();
  };
  return (
    <div style={{ display: 'flex', gap: 10 }}>
      {Array.from({ length: len }).map((_, i) => (
        <input key={i} ref={(el) => (refs.current[i] = el)} inputMode="numeric" maxLength={1}
          value={value[i] || ''} onChange={(e) => set(i, e.target.value)} onKeyDown={(e) => onKey(i, e)}
          style={{ flex: 1, minWidth: 0, height: 54, textAlign: 'center', boxSizing: 'border-box',
            fontFamily: 'Roboto, system-ui', fontSize: 22, fontWeight: 700, color: C.ink, borderRadius: 12,
            background: 'rgba(255,255,255,0.7)', outline: 'none',
            border: value[i] ? '1.6px solid #4F46E5' : '1px solid rgba(255,255,255,0.85)' }} />
      ))}
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════
// Forgot password — page 1: enter email, send OTP
// ════════════════════════════════════════════════════════════════════
function ForgotScreen({ onBack, onSent, initialUser = '' }) {
  const { useState } = React;
  const [username, setUsername] = useState(initialUser);
  const [err, setErr] = useState(null);
  const [loading, setLoading] = useState(false);
  const [focus, setFocus] = useState(false);
  const submit = () => {
    if (!username.trim()) { setErr('Please enter your username.'); return; }
    setErr(null); setLoading(true);
    setTimeout(() => { setLoading(false); onSent(username); }, 1200);
  };
  return (
    <AuthShell title="Forgot password?" onBack={onBack}
      subtitle="Enter your username and we’ll send a one-time code to your registered mobile number.">
      {fieldLabel('Username')}
      <LoginField placeholder="Enter your username" value={username} onChange={setUsername}
        focused={focus} onFocus={() => setFocus(true)} onBlur={() => setFocus(false)}
        icon={<svg width="18" height="18" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="8" r="4" stroke="currentColor" strokeWidth="1.8"/><path d="M4 20c0-3.3 3.6-6 8-6s8 2.7 8 6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/></svg>} />
      {err && <ErrBox msg={err} />}
      <div style={{ height: err ? 16 : 22 }} />
      <AuthBtn label="Send OTP" onClick={submit} loading={loading} />
      <div style={{ textAlign: 'center', marginTop: 16, fontSize: 13, color: C.muted, fontWeight: 500 }}>
        Back to <span onClick={onBack} style={{ color: C.primary, fontWeight: 700, cursor: 'pointer' }}>Sign in</span>
      </div>
    </AuthShell>
  );
}

// ════════════════════════════════════════════════════════════════════
// Reset password — page 2: enter OTP + new password + confirm
// ════════════════════════════════════════════════════════════════════
function ResetScreen({ username, onBack, onDone }) {
  const { useState } = React;
  const [otp, setOtp] = useState('');
  const [p1, setP1] = useState('');
  const [p2, setP2] = useState('');
  const [o1, setO1] = useState(true);
  const [o2, setO2] = useState(true);
  const [err, setErr] = useState(null);
  const [loading, setLoading] = useState(false);
  const [ok, setOk] = useState(false);
  const [focus, setFocus] = useState(null);
  const submit = () => {
    if (otp.length < 4) { setErr('Enter the 4-digit code sent to your email.'); return; }
    if (p1.length < 6) { setErr('Password must be at least 6 characters.'); return; }
    if (p1 !== p2) { setErr('Passwords do not match.'); return; }
    setErr(null); setLoading(true);
    setTimeout(() => { setLoading(false); setOk(true); setTimeout(onDone, 700); }, 1300);
  };
  const lock = <svg width="18" height="18" viewBox="0 0 24 24" fill="none"><rect x="4" y="10" width="16" height="10" rx="2.5" stroke="currentColor" strokeWidth="1.8"/><path d="M8 10V7a4 4 0 018 0v3" stroke="currentColor" strokeWidth="1.8"/></svg>;
  return (
    <AuthShell title="Reset password" onBack={onBack}
      subtitle={<React.Fragment>We sent a 4-digit code to the mobile number registered with <strong style={{ color: '#fff' }}>{username || 'your account'}</strong>. Enter it and set a new password.</React.Fragment>}>
      {fieldLabel('Verification code')}
      <OtpInput value={otp} onChange={setOtp} />
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 8 }}>
        <span style={{ fontSize: 12.5, color: C.muted }}>Didn’t get it? <span style={{ color: C.primary, fontWeight: 700, cursor: 'pointer' }}>Resend</span></span>
      </div>
      <div style={{ height: 14 }} />
      {fieldLabel('New password')}
      <LoginField type={o1 ? 'password' : 'text'} placeholder="At least 6 characters" value={p1} onChange={setP1}
        focused={focus === '1'} onFocus={() => setFocus('1')} onBlur={() => setFocus(null)}
        icon={lock} suffix={eyeToggle(o1, setO1)} />
      <div style={{ height: 14 }} />
      {fieldLabel('Confirm new password')}
      <LoginField type={o2 ? 'password' : 'text'} placeholder="Re-enter new password" value={p2} onChange={setP2}
        focused={focus === '2'} onFocus={() => setFocus('2')} onBlur={() => setFocus(null)}
        icon={lock} suffix={eyeToggle(o2, setO2)} />
      {err && <ErrBox msg={err} />}
      <div style={{ height: err ? 16 : 22 }} />
      <AuthBtn label="Reset password" onClick={submit} loading={loading} ok={ok} />
    </AuthShell>
  );
}

// ── Flow: welcome → login → forgot → reset → home (lazy-mounted, horizontal slide) ──
function Flow({ Welcome }) {
  const { useState } = React;
  const [screen, setScreen] = useState('welcome');
  const [visited, setVisited] = useState({ welcome: true });
  const [username, setUsername] = useState('');
  const [flash, setFlash] = useState(null);
  const order = ['welcome', 'login', 'forgot', 'reset', 'home'];
  const idx = order.indexOf(screen);
  const go = (name) => { setVisited((v) => ({ ...v, [name]: true })); setScreen(name); };
  const Home = window.HomeScreen;
  const panel = (name, node) => {
    if (!visited[name]) return null;
    const i = order.indexOf(name);
    return (
      <div key={name} style={{ position: 'absolute', inset: 0,
        transform: `translateX(${(i - idx) * 100}%)`,
        transition: 'transform .42s cubic-bezier(.4,0,.2,1)',
        pointerEvents: i === idx ? 'auto' : 'none' }}>{node}</div>
    );
  };
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden' }}>
      {panel('welcome', <Welcome onStart={() => { setFlash(null); go('login'); }} />)}
      {panel('login', <LoginScreen flash={flash}
        onBack={() => { setFlash(null); go('welcome'); }}
        onForgot={() => { setFlash(null); go('forgot'); }}
        onSignedIn={(u) => { setUsername(u || username); go('home'); }} />)}
      {panel('forgot', <ForgotScreen initialUser={username}
        onBack={() => go('login')}
        onSent={(u) => { setUsername(u); go('reset'); }} />)}
      {panel('reset', <ResetScreen username={username}
        onBack={() => go('forgot')}
        onDone={() => { setFlash('Password reset successfully. Please sign in.'); go('login'); }} />)}
      {panel('home', Home ? <Home username={username} onSignOut={() => setScreen('login')} /> : null)}
    </div>
  );
}

Object.assign(window, { WelcomeA, WelcomeB, WelcomeC, LoginScreen, ForgotScreen, ResetScreen, Flow, NavaColors: C, NavaMesh: Mesh });
