package com.streamify.app.downloads

import android.app.*
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import kotlinx.coroutines.*
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL

class DownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var worker: Job? = null
    @Volatile private var connection: HttpURLConnection? = null
    @Volatile private var current: String? = null
    private val store by lazy { DownloadStore.get(this) }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("downloads","Downloads",NotificationManager.IMPORTANCE_LOW))
        startForeground(700, notification("Preparing downloads"))
    }
    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this,0,Intent(this,DownloadsActivity::class.java),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this,"downloads").setSmallIcon(android.R.drawable.stat_sys_download).setContentTitle("Streamify downloads")
            .setContentText(text).setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val key = intent?.getStringExtra("key").orEmpty()
        when(intent?.action) {
            "pause" -> { store.change(key) { it.copy(state="paused") }; if(current==key) connection?.disconnect() }
            "resume" -> store.change(key) { it.copy(state="queued",error="") }
            "delete" -> { store.change(key) { it.copy(state="deleting") }; if(current==key) connection?.disconnect() }
        }
        if(worker?.isActive != true) worker = scope.launch {
            while(isActive) {
                store.items.value.filter { it.state=="deleting" }.forEach { store.remove(it.key) }
                val next = store.items.value.firstOrNull { it.state=="queued" } ?: break
                current=next.key
                withContext(Dispatchers.IO) {
                    val lock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"Streamify:download")
                    lock.acquire(60 * 60 * 1000L)
                    try { transfer(next) }
                    catch (e: Exception) {
                        val online = com.streamify.app.data.NetworkStatus.get(this@DownloadService).online.value
                        store.change(next.key) { if(it.state in listOf("resolving","downloading")) it.copy(state=if(online) "error" else "paused",error=if(online) e.localizedMessage ?: "Download interrupted. Tap retry." else "",bytes=store.file(it.key).length()) else it }
                    } finally { connection?.disconnect();connection=null;if(lock.isHeld) lock.release() }
                }
                current=null
            }
            stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()
        }
        return START_NOT_STICKY
    }
    private fun active(key: String) = store.get(key)?.state in listOf("resolving","downloading")
    private fun transfer(initial: DownloadItem) {
        val key = initial.key
        store.change(key) { it.copy(state="resolving",error="") }
        var item = store.get(key) ?: return
        val file = store.file(key)
        if(item.total>0 && file.length()==item.total) { store.change(key) { it.copy(state="complete",bytes=item.total) };return }
        var link = item.url.ifBlank { DownloadResolver.resolve(item) }
        if(!active(key)) return
        fun connect(url: String): HttpURLConnection {
            val c = URL(url).openConnection() as HttpURLConnection
            connection=c; c.connectTimeout=15000;c.readTimeout=20000
            c.setRequestProperty("Accept-Encoding","identity")
            if(file.length()>0) { c.setRequestProperty("Range","bytes=${file.length()}-"); if(item.validator.isNotBlank()) c.setRequestProperty("If-Range",item.validator) }
            return c
        }
        var c = connect(link)
        if(c.responseCode in listOf(401,403,404)) {
            c.disconnect();link=DownloadResolver.resolve(item)
            check(file.length()==0L || link==item.url || item.validator.isNotBlank()) { "Source changed. Delete this partial download and download again." }
            c=connect(link)
        }
        if(!active(key)) return
        check(c.url.protocol=="https") { "Unsupported download redirect." }
        val offset=file.length()
        val validator = c.getHeaderField("ETag")?.takeUnless { it.startsWith("W/") } ?: c.getHeaderField("Last-Modified").orEmpty()
        val type=c.contentType.orEmpty().substringBefore(';')
        check(type.startsWith("video/") || type=="application/octet-stream") { "Source did not return video. Try again later." }
        if(offset>0) {
            check(DownloadRange.valid(c.responseCode,c.getHeaderField("Content-Range"),offset,item.total)) { "Source cannot safely resume. Delete the partial download and try again." }
            check(item.validator.isBlank() || validator==item.validator) { "The video changed. Delete the partial download and try again." }
        } else check(c.responseCode==200) { "Download failed (${c.responseCode})." }
        val total=if(offset>0) item.total else c.contentLengthLong
        check(total>0) { "Source did not provide a download size." }
        check(store.directory.usableSpace > total-offset+32_000_000) { "Not enough free space for this download." }
        store.change(key) { if(active(key)) it.copy(url=link,validator=validator,total=total,bytes=offset,state="downloading") else it }
        c.inputStream.use { input -> RandomAccessFile(file,"rw").use { output ->
            output.seek(offset)
            val buffer=ByteArray(65536)
            var count=offset;var last=0L
            while(count<total && store.get(key)?.state=="downloading") {
                val n=input.read(buffer,0,minOf(buffer.size.toLong(),total-count).toInt())
                check(n>0) { "Connection ended early. Tap retry to resume." }
                output.write(buffer,0,n);count+=n
                if(System.currentTimeMillis()-last>1000) {
                    last=System.currentTimeMillis()
                    store.change(key) { it.copy(bytes=count) }
                    getSystemService(NotificationManager::class.java).notify(700,notification("${item.title} · ${count*100/total}%"))
                }
            }
            output.fd.sync()
            store.change(key) { it.copy(bytes=count,state=if(count==total && it.state=="downloading") "complete" else it.state) }
        } }
    }
    override fun onTimeout(startId: Int, fgsType: Int) { pauseAll();stopSelf() }
    private fun pauseAll() {
        store.items.value.filter { it.state in listOf("resolving","downloading","queued") }.forEach { store.change(it.key) { value -> value.copy(state="paused",bytes=store.file(value.key).length()) } }
        connection?.disconnect()
    }
    override fun onDestroy() { pauseAll();scope.cancel();super.onDestroy() }
}
