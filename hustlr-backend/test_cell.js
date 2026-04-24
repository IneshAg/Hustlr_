require('dotenv').config();
const { estimateLocation } = require('./src/services/cell_tower_service');

const payload = {
  radio: 'lte',
  cells: [
    { cellId: 17811, mcc: 310, mnc: 410, lac: 7033, signal: -65 }
  ]
};

console.log('Sending payload:', JSON.stringify(payload, null, 2));

estimateLocation(payload)
  .then(res => {
    console.log('\n✅ Success! Estimated Location:');
    console.log(JSON.stringify(res, null, 2));
  })
  .catch(err => {
    console.error('\n❌ Error:', err.message);
  });
