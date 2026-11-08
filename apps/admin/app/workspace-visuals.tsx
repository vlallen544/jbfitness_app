type IconName = 'inbox' | 'people' | 'calendar' | 'plans' | 'arrow' | 'refresh' | 'check';
const paths: Record<IconName, string> = {
  inbox: 'M4 5h16v14H4z M4 13h5l1 3h4l1-3h5',
  people: 'M15 20v-2a5 5 0 0 0-10 0v2 M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M19 20v-2a5 5 0 0 0-3-4.6 M17 3.2a4 4 0 0 1 0 7.6',
  calendar: 'M4 5h16v15H4z M8 3v4 M16 3v4 M4 10h16 M8 14h2 M14 14h2',
  plans: 'M5 4h14v17l-7-4-7 4z M9 8h6 M9 11h6',
  arrow: 'M5 12h14 M13 6l6 6-6 6',
  refresh: 'M20 7v5h-5 M4 17v-5h5 M6 7a7 7 0 0 1 12-1l2 3 M18 17a7 7 0 0 1-12 1l-2-3',
  check: 'm5 12 4 4L19 6',
};
export function WorkspaceIcon({name}: {name: IconName}) {
  return <svg className="workspace-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]}/></svg>;
}
export function TrainingMark() {
  return <svg className="training-mark" viewBox="0 0 400 220" fill="none" aria-hidden="true"><circle cx="216" cy="110" r="94" stroke="currentColor" strokeOpacity=".12"/><circle cx="216" cy="110" r="70" stroke="currentColor" strokeOpacity=".08"/><path d="M45 173h310 M74 189h220" stroke="currentColor" strokeOpacity=".15"/><g className="training-barbell" transform="rotate(-26 216 110)"><rect x="137" y="104" width="158" height="12" rx="6" fill="currentColor"/><rect x="129" y="73" width="20" height="74" rx="6" fill="currentColor"/><rect x="111" y="87" width="14" height="46" rx="5" fill="currentColor"/><rect x="283" y="73" width="20" height="74" rx="6" fill="currentColor"/><rect x="307" y="87" width="14" height="46" rx="5" fill="currentColor"/></g><path d="m329 42 4-12 4 12 12 4-12 4-4 12-4-12-12-4z" fill="#ff6268"/><circle cx="98" cy="55" r="4" fill="#ff6268"/></svg>;
}
export function Workload({open, resolved, onCustomers}: {open: number; resolved: number; onCustomers: () => void}) {
  const total = open + resolved, percent = total ? Math.round(resolved / total * 100) : 0;
  return <section className="workload-card"><div className="section-heading"><div><span className="eyebrow">AT A GLANCE</span><h2>Review workload</h2></div><WorkspaceIcon name="inbox"/></div><div className="workload-ring" role="img" aria-label={total ? `${resolved} of ${total} reviews in view resolved` : 'No reviews in view'}><svg viewBox="0 0 160 160" aria-hidden="true"><circle cx="80" cy="80" r="65" className="ring-track"/><circle cx="80" cy="80" r="65" className="ring-value" opacity={percent?1:0} pathLength="100" strokeDasharray={`${percent} 100`} transform="rotate(-90 80 80)"/></svg><div><strong>{total ? `${percent}%` : '—'}</strong><span>{total ? 'resolved in view' : 'no reviews yet'}</span></div></div><dl className="workload-legend"><div><dt><i/>Needs attention</dt><dd>{open}</dd></div><div><dt><i/>Resolved</dt><dd>{resolved}</dd></div></dl><p className="small muted">Open and resolved reviews in your current view.</p><div className="workspace-tip"><span className="eyebrow">KEEP COACHING PERSONAL</span><p>Check trainer assignments so shared questions reach the right person.</p><button className="text-button" onClick={onCustomers}>View customers <WorkspaceIcon name="arrow"/></button></div></section>;
}
