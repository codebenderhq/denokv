const KV_URL = "http://102.37.137.29:4512";
const ACCESS_TOKEN = "d4f2332c86df1ec68911c73b51c9dbad";

async function testDenoKV() {
  try {
    console.log('🔗 Testing DenoKV connection...');
    
    // Set the access token as environment variable
    Deno.env.set("DENO_KV_ACCESS_TOKEN", ACCESS_TOKEN);
    
    // Open KV connection using native Deno KV API
    const kv = await Deno.openKv(KV_URL);
    console.log('✅ KV connection opened successfully');
    
    // Test KV operations
    const testKey = ['test', 'key'];
    const testValue = 'Hello DenoKV!';
    
    // Set a value
    await kv.set(testKey, testValue);
    console.log('✅ Set operation successful - Key:', testKey, 'Value:', testValue);
    
    // Get the value
    const result = await kv.get(testKey);
    console.log('✅ Get operation successful - Retrieved:', result.value);
    
    // Clean up
    await kv.delete(testKey);
    console.log('✅ Delete operation successful - Removed key:', testKey);
    
    // Close connection
    kv.close();
    console.log('🎉 All DenoKV tests passed!');
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
}

testDenoKV();


  1 │# Check PostgreSQL logs for crash details
     2 │sudo tail -100 /var/log/postgresql/postgresql-*.log | grep -i "crash\|fatal\|panic"
     3 │
     4 │# Check for OOM kills
     5 │sudo dmesg | grep -i "out of memory\|killed process"
     6 │
     7 │# Check system resources
     8 │free -h
     9 │df -h