(function(){
  const Trainw=window.TrainwCore;
  if(!Trainw)return;
  const sb=Trainw.createClient();
  const LOGIN_HREF='/login?role=gym_owner';
  let currentGymId=null;
  let currentLang=localStorage.getItem('trainw_lang')||'fr';

  const COPY={
    fr:{pending:'En attente',confirmed:'Confirmee',completed:'Terminee',cancelled:'Annulee',pendingShort:'en attente',approved:'Approuve',approve:'Approuver',hold:'Mettre en attente',saved:'Mise a jour enregistree.',noBookings:'Aucune reservation a afficher.',noApprovals:'Aucun coach en attente.',queueEmpty:'Toutes les validations coach sont traitees.',nextSessions:'Prochaines reservations',pendingCount:'En attente',confirmedCount:'Confirmees',completedCount:'Terminees',cancelledCount:'Annulees'},
    en:{pending:'Pending',confirmed:'Confirmed',completed:'Completed',cancelled:'Cancelled',pendingShort:'pending',approved:'Approved',approve:'Approve',hold:'Set pending',saved:'Update saved.',noBookings:'No bookings to show.',noApprovals:'No coach approval is pending.',queueEmpty:'All coach approvals are up to date.',nextSessions:'Upcoming bookings',pendingCount:'Pending',confirmedCount:'Confirmed',completedCount:'Completed',cancelledCount:'Cancelled'},
    ar:{pending:'قيد الانتظار',confirmed:'مؤكد',completed:'مكتمل',cancelled:'ملغي',pendingShort:'قيد الانتظار',approved:'موافق عليه',approve:'موافقة',hold:'تعليق',saved:'تم حفظ التحديث.',noBookings:'لا توجد حجوزات للعرض.',noApprovals:'لا يوجد مدرب بانتظار الموافقة.',queueEmpty:'تمت معالجة كل الموافقات.',nextSessions:'الحجوزات القادمة',pendingCount:'قيد الانتظار',confirmedCount:'مؤكد',completedCount:'مكتمل',cancelledCount:'ملغي'}
  };

  function copy(key){return COPY[currentLang]?.[key]||COPY.fr[key]||key}
  function esc(value){return Trainw.escapeHTML(value)}
  function pillClass(status){return status==='approved'?'approved':status==='pending'?'pending':'other'}
  function bookingClass(status){return status==='confirmed'?'approved':status==='completed'?'approved':status==='cancelled'?'other':'pending'}
  function sessionTs(session){return new Date(`${session.session_date}T${session.start_time||'00:00:00'}`).getTime()}
  function fmtSession(session){const stamp=new Date(`${session.session_date}T${session.start_time||'00:00:00'}`);if(Number.isNaN(stamp.getTime()))return '-';return stamp.toLocaleString(Trainw.localeForLang(currentLang),{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'})}

  function renderBookingsOverview(sessions){
    const target=document.getElementById('gym-bookings-overview');
    if(!target)return;
    if(!sessions.length){target.innerHTML=`<p class="empty-state">${esc(copy('noBookings'))}</p>`;return}
    const counts={pending:0,confirmed:0,completed:0,cancelled:0};
    sessions.forEach(session=>{const status=session.status||'pending';if(counts[status]!==undefined)counts[status]+=1});
    const pending=sessions.filter(session=>(session.status||'pending')==='pending').sort((a,b)=>sessionTs(a)-sessionTs(b)).slice(0,5);
    target.innerHTML=`<div class="pilot-kpi-grid"><div class="pilot-kpi"><div class="pilot-kpi-label">${esc(copy('pendingCount'))}</div><div class="pilot-kpi-value">${counts.pending}</div></div><div class="pilot-kpi"><div class="pilot-kpi-label">${esc(copy('confirmedCount'))}</div><div class="pilot-kpi-value">${counts.confirmed}</div></div><div class="pilot-kpi"><div class="pilot-kpi-label">${esc(copy('completedCount'))}</div><div class="pilot-kpi-value">${counts.completed}</div></div><div class="pilot-kpi"><div class="pilot-kpi-label">${esc(copy('cancelledCount'))}</div><div class="pilot-kpi-value">${counts.cancelled}</div></div></div><div class="pilot-list" style="margin-top:16px;">${pending.length?pending.map(session=>`<article class="pilot-row"><div class="pilot-row-top"><div><div class="pilot-row-title">${esc(session.session_name||'Coach session')}</div><div class="pilot-row-meta">${esc(fmtSession(session))} · ${esc(session.coach?.name||'-')} · ${esc(session.client?.name||'-')}</div></div><span class="approval-pill ${bookingClass(session.status||'pending')}">${esc(copy(session.status||'pending'))}</span></div></article>`).join(''):`<p class="empty-state">${esc(copy('queueEmpty'))}</p>`}</div>`;
  }

  function renderScheduleOverview(sessions){
    const target=document.getElementById('schedule-booking-overview');
    if(!target)return;
    const upcoming=sessions.filter(session=>sessionTs(session)>=Date.now()&&(session.status||'pending')!=='cancelled').sort((a,b)=>sessionTs(a)-sessionTs(b)).slice(0,8);
    target.innerHTML=upcoming.length?`<div class="pilot-list">${upcoming.map(session=>`<article class="pilot-row"><div class="pilot-row-top"><div><div class="pilot-row-title">${esc(session.session_name||'Coach session')}</div><div class="pilot-row-meta">${esc(fmtSession(session))} · ${esc(session.coach?.name||'-')} · ${esc(session.client?.name||'-')}</div></div><span class="approval-pill ${bookingClass(session.status||'pending')}">${esc(copy(session.status||'pending'))}</span></div></article>`).join('')}</div>`:`<p class="empty-state">${esc(copy('noBookings'))}</p>`;
  }

  function coachCard(profile){
    const status=profile.approval_status||'pending';
    const rate=profile.price_per_session??profile.hourly_rate??0;
    const button=status==='approved'?`<button class="btn-secondary" type="button" data-approve-profile="${profile.id}" data-approval-status="pending">${esc(copy('hold'))}</button>`:`<button class="btn-primary" type="button" data-approve-profile="${profile.id}" data-approval-status="approved">${esc(copy('approve'))}</button>`;
    return `<article class="approval-card"><div class="approval-top"><div><div class="approval-name">${esc(profile.users?.name||'Coach')}</div><div class="approval-meta">${esc(profile.specialty||'Coach')} · ${esc(String(rate))} DT</div><div class="approval-meta">${esc(profile.users?.phone||profile.users?.email||'-')}</div></div><span class="approval-pill ${pillClass(status)}">${esc(status==='approved'?copy('approved'):copy('pendingShort'))}</span></div><div class="approval-actions">${button}</div></article>`;
  }

  function renderCoachApproval(coaches){
    const dashboard=document.getElementById('gym-coach-approval');
    const page=document.getElementById('coach-approval-list');
    const listHtml=coaches.length?`<div class="approval-list">${coaches.map(coachCard).join('')}</div>`:`<p class="empty-state">${esc(copy('noApprovals'))}</p>`;
    if(dashboard)dashboard.innerHTML=listHtml;
    if(page)page.innerHTML=listHtml;
  }

  async function refresh(){
    currentLang=localStorage.getItem('trainw_lang')||currentLang;
    const ctx=await Trainw.auth.getContext(sb,{expectedRoles:['gym_owner','gym','admin'],loginHref:LOGIN_HREF,redirectOnMismatch:false});
    if(!ctx.session||!ctx.profile)return;
    currentGymId=ctx.profile.gym_id||null;
    if(!currentGymId){
      renderBookingsOverview([]);
      renderScheduleOverview([]);
      renderCoachApproval([]);
      return;
    }

    const [sessionsRes,coachesRes]=await Promise.all([
      Trainw.api.run(sb.from('sessions').select('id,session_date,start_time,end_time,status,session_name,client:users!sessions_client_id_fkey(name),coach:users!sessions_coach_id_fkey(name)').eq('gym_id',currentGymId).order('session_date',{ascending:true}).order('start_time',{ascending:true}),{context:'gym pilot sessions',fallback:[]}),
      Trainw.api.run(sb.from('coach_profiles').select('id,user_id,gym_id,approval_status,approved_at,price_per_session,hourly_rate,specialty,users:users!coach_profiles_user_id_fkey(id,name,phone,email,gym_id)').eq('gym_id',currentGymId).order('created_at',{ascending:false}),{context:'gym pilot coaches',fallback:[]})
    ]);

    const sessions=Array.isArray(sessionsRes.data)?sessionsRes.data:[];
    const coaches=Array.isArray(coachesRes.data)?coachesRes.data:[];
    renderBookingsOverview(sessions);
    renderScheduleOverview(sessions);
    renderCoachApproval(coaches);
  }

  async function updateCoachApproval(profileId,status){
    const payload={approval_status:status,approved_at:status==='approved'?new Date().toISOString():null};
    const result=await Trainw.api.run(sb.from('coach_profiles').update(payload).eq('id',profileId),{context:'gym pilot coach approval',fallback:null});
    if(result.error)return;
    Trainw.ui.showToast(copy('saved'),'success');
    if(typeof loadCoaches==='function')await Promise.allSettled([loadCoaches(),typeof loadDashboardStats==='function'?loadDashboardStats():Promise.resolve(),typeof loadSchedule==='function'?loadSchedule():Promise.resolve()]);
    await refresh();
  }

  function bindApproval(targetId){
    document.getElementById(targetId)?.addEventListener('click',event=>{
      const button=event.target.closest('[data-approve-profile]');
      if(!button)return;
      updateCoachApproval(button.dataset.approveProfile,button.dataset.approvalStatus);
    });
  }

  function bind(){
    bindApproval('gym-coach-approval');
    bindApproval('coach-approval-list');
    window.addEventListener('focus',()=>refresh());
    document.querySelectorAll('.nav-item').forEach(item=>item.addEventListener('click',()=>setTimeout(refresh,150)));
  }

  bind();
  refresh();
})();
