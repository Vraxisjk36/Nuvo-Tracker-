window.NuvoCloud=(function(){
let sb=null,user=null,channel=null;
function configured(){const c=window.NUVO_CONFIG||{};return !!(c.supabaseUrl&&c.supabaseAnonKey&&window.supabase)}
async function init(onChange){if(!configured())return {mode:"local"};sb=window.supabase.createClient(NUVO_CONFIG.supabaseUrl,NUVO_CONFIG.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});const {data}=await sb.auth.getSession();user=data.session?.user||null;sb.auth.onAuthStateChange((_e,s)=>{user=s?.user||null;onChange&&onChange({auth:true,user})});return {mode:"cloud",user}}
async function signIn(email,password){return sb.auth.signInWithPassword({email,password})}
async function signOut(){return sb.auth.signOut()}
async function load(){if(!sb||!user)return null;const [p,b,s,n,t,a]=await Promise.all([
sb.from("projects").select("*").order("due"),
sb.from("batches").select("*").order("production_date"),
sb.from("shipments").select("*").order("shipment_date"),
sb.from("project_notes").select("*").order("created_at",{ascending:false}),
sb.from("target_history").select("*").order("created_at",{ascending:false}),
sb.from("activity_log").select("*").order("created_at",{ascending:false})
]);for(const r of [p,b,s,n,t,a])if(r.error)throw r.error;return {
projects:p.data.map(x=>({id:x.id,client:x.client,name:x.name,location:x.location,product:x.product,target:x.production_target_sets,deliveryTarget:x.delivery_target_sets,due:x.due,priority:x.priority,baseWeight:+x.base_weight,activatorWeight:+x.activator_weight,dilution:+x.dilution,status:x.status,notes:x.notes,created:x.created_at?.slice(0,10)})),
batches:b.data.map(x=>({id:x.id,projectId:x.project_id,type:x.type,qty:x.qty,epicure:+x.epicure,dilute:+x.dilute,materials:x.materials||[],date:x.production_date,expiry:x.expiry,code:x.code,notes:x.notes,status:x.status,allocated:x.allocated})),
shipments:s.data.map(x=>({id:x.id,projectId:x.project_id,base:x.base_qty,activator:x.activator_qty,date:x.shipment_date,notes:x.notes})),
projectNotes:n.data.map(x=>({id:x.id,projectId:x.project_id,text:x.body,date:x.created_at?.slice(0,10)})),
targetHistory:t.data.map(x=>({id:x.id,projectId:x.project_id,from:x.old_target,to:x.new_target,reason:x.reason,date:x.created_at})),
activity:a.data.map(x=>({id:x.id,projectId:x.project_id,text:x.event,date:x.created_at})),_ledgerMigrated:true}}
async function insert(table,row){if(!sb)return null;const {data,error}=await sb.from(table).insert(row).select().single();if(error)throw error;return data}
async function update(table,id,row){if(!sb)return null;const {error}=await sb.from(table).update(row).eq("id",id);if(error)throw error}
function watch(cb){if(!sb||channel)return;channel=sb.channel("nuvo-live").on("postgres_changes",{event:"*",schema:"public"},()=>cb&&cb()).subscribe()}
return{configured,init,signIn,signOut,load,insert,update,watch,get user(){return user}}
})();