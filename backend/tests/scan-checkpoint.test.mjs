import {test} from 'node:test';
import assert from 'node:assert/strict';
import {saveCheckpoint} from '../../scripts/lib/scan-checkpoint.mjs';
test('checkpoint retries transient file sharing failures without deleting prior state',async()=>{
  let writes=0,renames=0;const waits=[];
  await saveCheckpoint('state.json',{usage:2},{writeFile:async()=>{writes++;},rename:async()=>{renames++;if(renames<3)throw Object.assign(Error('private path'),{code:'EPERM'});}},async ms=>waits.push(ms));
  assert.equal(writes,1);assert.equal(renames,3);assert.deepEqual(waits,[200,400]);
});
test('checkpoint stops on persistent or non-transient errors and hides raw details',async()=>{
  for(const code of ['EPERM','ENOSPC']) {
    let calls=0;
    await assert.rejects(saveCheckpoint('state.json',{}, {writeFile:async()=>{},rename:async()=>{calls++;throw Object.assign(Error('private details'),{code});}},async()=>{}),/^Error: checkpoint_write_failed$/);
    assert.equal(calls,code==='EPERM'?6:1);
  }
});
