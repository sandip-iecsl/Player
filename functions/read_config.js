const admin = require('firebase-admin');
admin.initializeApp({
  projectId: 'aura-player-e7c87'
});
const db = admin.firestore();
db.collection('app_config').doc('map_settings').get().then(doc => {
  console.log('DOC DATA:', doc.data());
}).catch(err => {
  console.error('ERROR:', err);
});
