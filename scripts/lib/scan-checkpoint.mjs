import {writeFile,rename} from 'node:fs/promises';
// Retry only transient Windows file sharing errors. Never delete the good checkpoint.
export async function saveCheckpoint(destination, value, io = {writeFile,rename}, wait = ms => new Promise(resolve=>setTimeout(resolve,ms))) {
  const temporary=destination+'.tmp';
  try {
    await io.writeFile(temporary,JSON.stringify(value,null,2));
    for(let attempt=0;;attempt++) {
      try {await io.rename(temporary,destination);return;}
      catch(error) {
        if(!['EPERM','EACCES','EBUSY'].includes(error.code) || attempt>=5)throw error;
        await wait(200*(attempt+1));
      }
    }
  } catch {throw Error('checkpoint_write_failed');}
}
