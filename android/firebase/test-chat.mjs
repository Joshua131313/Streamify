import {initializeApp,deleteApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInAnonymously} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,doc,setDoc,updateDoc,getDoc,serverTimestamp,deleteField,terminate} from 'firebase/firestore';
import assert from 'node:assert/strict';
const apps=[];
async function client(name){let app=initializeApp({projectId:'demo-streamify-chat',apiKey:'demo-test',appId:'demo-test'},name);apps.push(app);let auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9098',{disableWarnings:true});let db=getFirestore(app);connectFirestoreEmulator(db,'127.0.0.1',8086);await signInAnonymously(auth);return {db,uid:auth.currentUser.uid};}
const a=await client('a'),b=await client('b');
const room='test-'+Date.now(),path=`live-chats/${room}/messages/first`,ref=doc(a.db,path),other=doc(b.db,path);
const message={message:'Go team',senderId:a.uid,senderName:'Fan A',sentAt:serverTimestamp(),reactions:[]};
await setDoc(ref,message);
const emoji='\u{1f44d}';
await updateDoc(ref,{[`reactionVotes.${a.uid}`]:emoji});
await updateDoc(other,{[`reactionVotes.${b.uid}`]:emoji});
assert.equal(Object.keys((await getDoc(ref)).data().reactionVotes).length,2);
async function denied(fn){await assert.rejects(fn,e=>e.code==='permission-denied');}
await denied(()=>updateDoc(other,{[`reactionVotes.${a.uid}`]:deleteField()}));
await denied(()=>updateDoc(other,{message:'tampered'}));
await denied(()=>updateDoc(ref,{[`reactionVotes.${a.uid}`]:'invalid'}));
await denied(()=>setDoc(doc(a.db,`live-chats/${room}/messages/forged`),{...message,reactionVotes:{[b.uid]:emoji}}));
await setDoc(doc(b.db,`live-chats/${room}/messages/reply`),{...message,senderId:b.uid,senderName:'Fan B',replyTo:{id:'first',sender:'Fan A',message:'Go team'}});
await denied(()=>setDoc(doc(b.db,`live-chats/${room}/messages/fake-reply`),{...message,senderId:b.uid,replyTo:{id:'first',sender:'Fan A',message:'Fake quote'}}));
await updateDoc(ref,{[`reactionVotes.${a.uid}`]:deleteField()});
assert.equal((await getDoc(ref)).data().reactionVotes[a.uid],undefined);
await updateDoc(other,{[`reactionVotes.${b.uid}`]:'\u{1f525}'});
console.log('PASS: guest messages, reactions add/change/remove, replies; cross-user votes, text edits, invalid emoji, forged votes and forged replies denied.');
for(const app of apps){await terminate(getFirestore(app));await deleteApp(app);}
