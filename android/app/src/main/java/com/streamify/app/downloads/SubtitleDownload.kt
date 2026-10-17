package com.streamify.app.downloads

import java.net.URL
import java.net.HttpURLConnection

object SubtitleDownload {
    fun fetch(url:String):ByteArray {
        require(URL(url).protocol=="https")
        val c=URL(url).openConnection() as HttpURLConnection
        c.connectTimeout=8000;c.readTimeout=8000
        try {
            check(c.responseCode==200 && c.url.protocol=="https") {"Subtitle source unavailable"}
            check(c.contentLengthLong<=2_000_000) {"Subtitle file too large"}
            val bytes=c.inputStream.use {input->
                val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192)
                while(true) {val n=input.read(buffer);if(n<0) break;check(out.size()+n<=2_000_000);out.write(buffer,0,n)}
                out.toByteArray()
            }
            OfflineSubtitles.parse(bytes.toString(Charsets.UTF_8))
            return bytes
        } finally {c.disconnect()}
    }
    fun save(store:DownloadStore,key:String,bytes:ByteArray,active:()->Boolean) {
        synchronized(store) {
            if(!active() || store.get(key)==null || store.subtitleFile(key).exists()) return
            val file=android.util.AtomicFile(store.subtitleFile(key));var output:java.io.FileOutputStream?=null
            try {output=file.startWrite();output.write(bytes);file.finishWrite(output)} catch(e:Exception) {file.failWrite(output);throw e}
        }
    }
}
