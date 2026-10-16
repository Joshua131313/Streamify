package com.streamify.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.streamify.app.data.League

@Composable
fun LeagueFilterDialog(selected: Set<League>, dismiss: () -> Unit, apply: (Set<League>) -> Unit) {
    var draft by remember(selected) { mutableStateOf(selected) }
    AlertDialog(onDismissRequest = dismiss, title = { Text("Filter leagues") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Choose the leagues shown in games and calendar dots.", color = Muted)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    SecondaryButton(onClick = { draft = League.entries.toSet() }) { Text("Select all") }
                    SecondaryButton(onClick = { draft = emptySet() }) { Text("Clear") }
                }
                League.entries.forEach { league ->
                    Surface(shape = RoundedCornerShape(14.dp), color = Panel) {
                        Row(Modifier.fillMaxWidth().toggleable(league in draft, role = Role.Checkbox) { checked ->
                            draft = if (checked) draft + league else draft - league
                        }.padding(12.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            LeagueLogo(league, Modifier.size(30.dp))
                            Text(league.name, Modifier.weight(1f))
                            Checkbox(checked = league in draft, onCheckedChange = null)
                        }
                    }
                }
                if (draft.isEmpty()) Text("Choose at least one league.", color = Muted)
            }
        },
        confirmButton = { SecondaryButton(enabled = draft.isNotEmpty(), onClick = { apply(draft) }) { Text("Apply filters") } },
        dismissButton = { SecondaryButton(onClick = dismiss) { Text("Cancel") } })
}
