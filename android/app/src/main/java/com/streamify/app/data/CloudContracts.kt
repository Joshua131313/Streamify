package com.streamify.app.data

import java.util.Locale

data class CloudMediaRef(val id: Int, val type: MediaType) {
    val key get() = "${type.path}:$id"
    val documentId get() = "${type.path}-$id"
    companion object {
        fun parse(data: Map<String, Any?>): CloudMediaRef? {
            val id = (data["mediaId"] as? Number)?.toInt()?.takeIf { it > 0 } ?: return null
            val type = MediaType.entries.firstOrNull { it.path == data["mediaType"] } ?: return null
            return CloudMediaRef(id, type)
        }
    }
}

fun webTeamAbbreviation(league: League, abbreviation: String): String {
    val value = abbreviation.uppercase(Locale.ROOT)
    return when (league) {
        League.NHL -> mapOf("LAK" to "LA", "NJD" to "NJ", "SJS" to "SJ", "TBL" to "TB", "UTAH" to "UTA")[value] ?: value
        League.MLB -> mapOf("CWS" to "CHW", "WSN" to "WSH", "OAK" to "ATH")[value] ?: value
        League.NBA -> mapOf("NYK" to "NY", "GSW" to "GS", "SAS" to "SA", "NOP" to "NO", "UTA" to "UTAH")[value] ?: value
        else -> value
    }
}
fun teamCloudKey(league: League, abbreviation: String) = "${league.name}:${webTeamAbbreviation(league, abbreviation)}"
fun chatRoomId(game: Game) = "${webTeamAbbreviation(game.league, game.away.abbreviation)}-${webTeamAbbreviation(game.league, game.home.abbreviation)}"
