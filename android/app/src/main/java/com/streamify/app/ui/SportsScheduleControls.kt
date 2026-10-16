package com.streamify.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ViewList
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.streamify.app.data.*
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import java.time.*
import java.time.format.DateTimeFormatter

@Composable
fun SportsLoading(label: String = "Updating scores") {
    Row(Modifier.padding(horizontal = 20.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CircularProgressIndicator(Modifier.size(16.dp), color = Muted, strokeWidth = 1.5.dp)
        Text(label, color = Muted, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
fun GamePlaceholder() {
    Surface(Modifier.fillMaxWidth().padding(horizontal = 20.dp), color = Panel, shape = RoundedCornerShape(20.dp)) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Box(Modifier.width(80.dp).height(10.dp).clip(CircleShape).background(Muted.copy(alpha = .12f)))
            repeat(2) { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(Modifier.size(40.dp).clip(CircleShape).background(Muted.copy(alpha = .10f)))
                Box(Modifier.fillMaxWidth(.65f).height(14.dp).clip(CircleShape).background(Muted.copy(alpha = .10f)))
            } }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SportsScheduleControls(day: LocalDate, layout: String, loading: Boolean, selectedLeagues: Set<League>, finalOnly: Boolean, select: (LocalDate) -> Unit, changeLayout: (String) -> Unit, refresh: () -> Unit) {
    if (finalOnly) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Final results", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
            IconButton(onClick = refresh, enabled = !loading) { Icon(Icons.Rounded.Refresh, "Refresh scores", tint = Muted) }
        }
        return
    }
    var picker by remember { mutableStateOf(false) }
    val today = LocalDate.now()
    val window = sportsDateWindow(today, finalOnly = finalOnly)
    val end = window.endInclusive
    val allEvents by produceState<CalendarEvents?>(null, today) { value = calendarEvents(today) }
    val events = allEvents?.forLeagues(selectedLeagues)
    LaunchedEffect(today, day, finalOnly) { if (day !in window) select(day.coerceIn(today, end)) }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            SecondaryButton(onClick = { picker = true }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 12.dp)) {
                Text(if (layout == "Calendar") "Jump to date" else day.format(DateTimeFormatter.ofPattern("MMMM yyyy")), Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurface, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                Icon(Icons.Rounded.KeyboardArrowDown, null, Modifier.size(20.dp), tint = Muted)
            }
            SecondaryButton(onClick = { select(today) }) { Text("Today", fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
            IconButton(onClick = refresh, enabled = !loading) { Icon(Icons.Rounded.Refresh, "Refresh scores", Modifier.size(20.dp), tint = Muted) }
        }
        LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(listOf("List", "Slider", "Calendar")) { value -> FilterPill(value, value == layout, { changeLayout(value) }, leading = {
                Icon(when(value) { "Calendar" -> Icons.Rounded.CalendarMonth; "Slider" -> Icons.Rounded.ViewCarousel; else -> Icons.AutoMirrored.Rounded.ViewList }, null, Modifier.size(16.dp))
            }) }
        }
        if (layout == "Calendar") Surface(Modifier.padding(horizontal = 20.dp).fillMaxWidth(), color = Panel, contentColor = MaterialTheme.colorScheme.onSurface, shape = RoundedCornerShape(20.dp)) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (finalOnly) "Final results" else "Next 14 days", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(4.dp))
                Text(if (finalOnly) "Today only. Past games will be available in a future update." else "${today.format(DateTimeFormatter.ofPattern("MMM d"))} to ${end.format(DateTimeFormatter.ofPattern("MMM d"))}", color = Muted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 4.dp))
                (0L..java.time.temporal.ChronoUnit.DAYS.between(today, end)).chunked(7).forEach { week ->
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        week.forEach { offset ->
                            val date = today.plusDays(offset)
                            DateCell(date, day, today, (if (finalOnly) Modifier.width(64.dp) else Modifier.weight(1f)), true, events, select)
                        }
                    }
                }
            }
        } else {
            LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items((0L..java.time.temporal.ChronoUnit.DAYS.between(today, end)).map { today.plusDays(it) }, key = { it.toString() }) { date -> DateCell(date, day, today, Modifier.width(64.dp), true, events, select) }
            }
        }
        LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(League.entries.filter { it in selectedLeagues }) { league ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Box(Modifier.size(6.dp).clip(CircleShape).background(leagueDotColor(league)))
                    Text(league.name, color = Muted, fontSize = 10.sp)
                }
            }
        }
        if (events == null) SportsLoading("Finding games over the next two weeks")
        else if (events!!.unavailable.isNotEmpty()) Text("Some event markers are unavailable. Select a day to check its schedule.", Modifier.padding(horizontal = 20.dp), color = Muted, style = MaterialTheme.typography.bodySmall)
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(enabled = day > today, onClick = { select(day.minusDays(1)) }, modifier = Modifier.size(40.dp)) { Icon(Icons.Rounded.ChevronLeft, "Previous day", Modifier.size(18.dp)) }
            Text(if (day == today) "Today’s games" else day.format(DateTimeFormatter.ofPattern("EEE, MMM d")), Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center, style = MaterialTheme.typography.titleSmall)
            IconButton(enabled = day < end, onClick = { select(day.plusDays(1)) }, modifier = Modifier.size(40.dp)) { Icon(Icons.Rounded.ChevronRight, "Next day", Modifier.size(18.dp)) }
        }
    }
    if (picker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            yearRange = today.year..end.year,
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate() in window
                override fun isSelectableYear(year: Int) = year in today.year..end.year
            })
        DatePickerDialog(onDismissRequest = { picker = false }, confirmButton = { SecondaryButton(onClick = {
            state.selectedDateMillis?.let { select(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }; picker = false
        }) { Text("Apply") } }, dismissButton = { SecondaryButton(onClick = { picker = false }) { Text("Cancel") } }) { DatePicker(state) }
    }
}

@Composable
private fun DateCell(date: LocalDate, selected: LocalDate, today: LocalDate, modifier: Modifier, weekday: Boolean, events: CalendarEvents?, select: (LocalDate) -> Unit) {
    val active = date == selected
    val leagues = League.entries.filter { it in events?.days?.get(date).orEmpty() }
    val description = date.format(DateTimeFormatter.ofPattern("EEEE, MMMM d")) + ": " + when {
        events == null -> "Loading games"
        leagues.isNotEmpty() -> leagues.joinToString { it.name } + " games" + if (events.unavailable.isNotEmpty()) "; other leagues unavailable" else ""
        events.unavailable.isNotEmpty() -> "Schedule markers unavailable"
        else -> "No games scheduled"
    }
    Surface(onClick = { select(date) }, modifier = modifier.semantics { contentDescription = description }, shape = RoundedCornerShape(14.dp),
        color = if (active) MaterialTheme.colorScheme.onSurface else if (weekday) Panel else Color.Transparent,
        contentColor = if (active) MaterialTheme.colorScheme.surface else MaterialTheme.colorScheme.onSurface,
        border = if (date == today && !active) BorderStroke(1.dp, Muted.copy(alpha = .4f)) else null) {
        Column(Modifier.heightIn(min = if (weekday) 68.dp else 48.dp).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            if (weekday) Text(date.format(DateTimeFormatter.ofPattern("EEE")), fontSize = 12.sp, maxLines = 1)
            Text(date.dayOfMonth.toString(), fontSize = 16.sp, fontWeight = if (active) FontWeight.Bold else FontWeight.Medium)
            Row(Modifier.height(5.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                leagues.forEach { league -> Box(Modifier.size(4.dp).clip(CircleShape).background(leagueDotColor(league))) }
            }
        }
    }
}

private fun leagueDotColor(league: League): Color = when (league) {
    League.NFL -> Color(0xFF399BF5)
    League.NBA -> Color(0xFFEF883D)
    League.WNBA -> Color(0xFFDB65B5)
    League.NHL -> Color(0xFF46BDB3)
    League.MLB -> Color(0xFF9473E8)
}
