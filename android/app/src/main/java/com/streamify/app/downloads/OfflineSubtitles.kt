package com.streamify.app.downloads

/** Local UTF-8 SRT/WebVTT cues. No network access or remote markup. */
object OfflineSubtitles {
    data class Cue(val start:Long,val end:Long,val text:String)
    fun parse(text:String):List<Cue> {
        require(text.length<=2_000_000) {"Subtitle file must be smaller than 2 MB."}
        fun time(value:String):Long {
            val parts=value.replace(',', '.').split(':')
            require(parts.size in 2..3)
            return ((if(parts.size==3) parts[0].toLong()*3600 else 0)+parts[parts.size-2].toLong()*60)*1000+(parts.last().toDouble()*1000).toLong()
        }
        val lines=text.removePrefix("\uFEFF").replace("\r","").lines();val cues=mutableListOf<Cue>();var i=0
        while(i<lines.size) {
            val line=lines[i++]
            if(!line.contains("-->")) continue
            val timing=line.split("-->",limit=2)
            val start=time(timing[0].trim());val end=time(timing[1].trim().substringBefore(' '))
            val body=mutableListOf<String>();while(i<lines.size && lines[i].isNotBlank()) body.add(lines[i++])
            if(end>start) cues.add(Cue(start,end,body.joinToString("\n").replace(Regex("<[^>]*>"),"")))
            require(cues.size<=20000) {"Too many subtitle cues."}
        }
        require(cues.isNotEmpty()) {"No supported subtitles found. Choose a UTF-8 SRT or VTT file."}
        return cues.sortedBy {it.start}
    }
    fun at(cues:List<Cue>,position:Long):String {
        var low=0;var high=cues.lastIndex;var found=-1
        while(low<=high) {val mid=(low+high)/2;if(cues[mid].start<=position){found=mid;low=mid+1}else high=mid-1}
        return cues.getOrNull(found)?.takeIf {position<it.end}?.text.orEmpty()
    }
}
