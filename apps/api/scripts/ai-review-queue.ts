import { Database } from '../src/database';
// Trusted local operator command. It does not notify trainers or approve plans.
async function main() {
  const db=new Database();
  try {
    const result=await db.pool.query("SELECT r.id,r.customer_id,r.status,r.stage,r.message,r.created_at FROM ai_planning_runs r WHERE r.status='review_needed' AND NOT EXISTS(SELECT 1 FROM staff_review_state s WHERE s.kind='planning' AND s.source_id=r.id AND s.status='resolved') ORDER BY r.created_at LIMIT 100");
    const coaching=await db.pool.query("SELECT c.id,c.customer_id,c.kind,c.response->>'reviewReason' AS reason,c.created_at FROM coaching_turns c WHERE NOT c.deleted AND c.status='completed' AND c.response->>'needsTrainerReview'='true' AND NOT EXISTS(SELECT 1 FROM staff_review_state s WHERE s.kind='coaching' AND s.source_id=c.id AND s.status='resolved') ORDER BY c.created_at LIMIT 100");
    console.log(JSON.stringify({reviews:result.rows,coachingReviews:coaching.rows,limit:100},null,2));
  }finally{await db.pool.end();}
}
main().catch(()=>{console.error('Could not read the AI review queue. Check database access.');process.exitCode=1;});
