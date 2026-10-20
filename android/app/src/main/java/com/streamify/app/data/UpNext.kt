package com.streamify.app.data

import java.time.LocalDate
import kotlinx.coroutines.ensureActive

data class NextEpisode(val season:Int,val episode:Int,val title:String)

suspend fun StreamifyRepository.nextEpisode(media:Media,season:Int,episode:Int):NextEpisode? {
    fun aired(item:Episode)=episodeAvailable(item)
    val current=episodes(media.id,season,media.type)
    current.firstOrNull {it.number==episode+1 && aired(it)}?.let {return NextEpisode(season,it.number,it.title)}
    if(current.maxOfOrNull {it.number}!=episode) return null
    val nextSeason=details(media).seasons.filter {it.number>season && it.count>0}.minByOrNull {it.number} ?: return null
    return episodes(media.id,nextSeason.number,media.type).firstOrNull {it.number==1 && aired(it)}?.let {NextEpisode(nextSeason.number,it.number,it.title)}
}

// Missing dates are common for catalog entries; only a known future date blocks playback.
internal fun episodeAvailable(item: Episode, today: LocalDate = LocalDate.now()): Boolean =
    item.date.isBlank() || item.date == "null" ||
        runCatching { !LocalDate.parse(item.date).isAfter(today) }.getOrDefault(false)

internal suspend fun <T> retryEpisodeLookup(load: suspend () -> T): T {
    repeat(2) { attempt ->
        try { return kotlinx.coroutines.withTimeout(12_000) { load() } }
        catch (error: Exception) {
            kotlin.coroutines.coroutineContext.ensureActive()
            kotlinx.coroutines.delay(500L * (attempt + 1))
        }
    }
    return kotlinx.coroutines.withTimeout(12_000) { load() }
}
