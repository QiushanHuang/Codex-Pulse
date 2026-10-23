import test from 'node:test';
import assert from 'node:assert/strict';
import {lightingState} from '../scripts/keyboard.mjs';
test('an async question can need an answer while the turn still runs',()=>{
 const state=lightingState({generatedAt:100,tasks:[
  {status:'waiting_input',isRunning:true},{status:'waiting_input',isRunning:false}
 ]},101);
 assert.equal(state.activeCount,1);
 assert.equal(state.mode,'running');
});
