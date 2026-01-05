const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize with default credentials (from gcloud/firebase login)
initializeApp({
  projectId: 'luxor-browser-sync',
});

const db = getFirestore();

async function checkData() {
  try {
    // List all users
    const usersSnapshot = await db.collection('users').get();

    console.log('=== FIRESTORE DATABASE CHECK ===\n');
    console.log('Total users: ' + usersSnapshot.size + '\n');

    for (const userDoc of usersSnapshot.docs) {
      console.log('\n User: ' + userDoc.id);
      console.log('──────────────────────────────────────────────────');

      // Check data stored directly in user document
      const userData = userDoc.data();
      if (userData) {
        const fields = Object.keys(userData);
        console.log('  Fields in user doc: ' + fields.join(', '));

        for (const field of fields) {
          const value = userData[field];
          if (Array.isArray(value)) {
            console.log('    - ' + field + ': ' + value.length + ' items (array)');
          } else if (typeof value === 'object' && value !== null) {
            console.log('    - ' + field + ': object with keys: ' + Object.keys(value).join(', '));
          } else {
            console.log('    - ' + field + ': ' + (typeof value));
          }
        }
      }

      // Check subcollections
      const collections = ['bookmarks', 'history', 'reading_list', 'settings', 'passwords', 'open_tabs'];

      console.log('\n  Subcollections:');
      for (const col of collections) {
        try {
          const colSnapshot = await db.collection('users').doc(userDoc.id).collection(col).get();
          if (colSnapshot.size > 0) {
            console.log('    - ' + col + ': ' + colSnapshot.size + ' documents');
          }
        } catch (e) {
          // Skip errors
        }
      }
    }

  } catch (error) {
    console.error('Error:', error.message);
  }
  process.exit(0);
}

checkData();
