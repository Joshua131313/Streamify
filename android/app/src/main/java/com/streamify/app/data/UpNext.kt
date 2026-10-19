package com.streamify.app.data

import java.time.LocalDate

data class NextEpisode(val season:Int,val episode:Int,val title:String)

suspend fun StreamifyRepository.nextEpisode(media:Media,season:Int,episode:Int):NextEpisode? {
    fun aired(item:Episode)=item.date.isNotBlank() && item.date<=LocalDate.now().toString()
    val current=episodes(media.id,season,media.type)
    current.firstOrNull {it.number==episode+1 && aired(it)}?.let {return NextEpisode(season,it.number,it.title)}
    if(current.maxOfOrNull {it.number}!=episode) return null
    val nextSeason=details(media).seasons.filter {it.number>season && it.count>0}.minByOrNull {it.number} ?: return null
    return episodes(media.id,nextSeason.number,media.type).firstOrNull {it.number==1 && aired(it)}?.let {NextEpisode(nextSeason.number,it.number,it.title)}
}
