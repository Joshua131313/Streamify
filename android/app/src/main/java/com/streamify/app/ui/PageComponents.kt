package com.streamify.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Shared controls for the browsing and detail pages. Home keeps its compact shelf controls. */
@Composable
fun PageSearchField(value: String, onValueChange: (String) -> Unit, hint: String, modifier: Modifier = Modifier) {
    TextField(value, onValueChange, modifier.fillMaxWidth(), singleLine = true,
        placeholder = { Text(hint, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium) },
        leadingIcon = { Icon(Icons.Rounded.Search, null, tint = Muted) },
        trailingIcon = { if (value.isNotEmpty()) IconButton(onClick = { onValueChange("") }) { Icon(Icons.Rounded.Close, "Clear search") } },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        shape = RoundedCornerShape(16.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Panel, unfocusedContainerColor = Panel,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
            cursorColor = StreamRed, focusedTextColor = MaterialTheme.colorScheme.onSurface,
            unfocusedTextColor = MaterialTheme.colorScheme.onSurface))
}

@Composable
fun FilterPill(label: String, selected: Boolean, onClick: () -> Unit, enabled: Boolean = true,
               leading: (@Composable () -> Unit)? = null) {
    FilterChip(selected, onClick, enabled = enabled, shape = RoundedCornerShape(12.dp),
        label = { Text(label, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium, maxLines = 1, softWrap = false) },
        leadingIcon = leading,
        border = FilterChipDefaults.filterChipBorder(enabled, selected,
            borderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .10f), selectedBorderColor = Color.Transparent),
        colors = FilterChipDefaults.filterChipColors(
            containerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .06f),
            labelColor = Muted, selectedContainerColor = MaterialTheme.colorScheme.onSurface,
            selectedLabelColor = MaterialTheme.colorScheme.surface,
            selectedLeadingIconColor = MaterialTheme.colorScheme.surface))
}

@Composable
fun SectionLabel(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold)
        subtitle?.let { Text(it, color = Muted, style = MaterialTheme.typography.bodyMedium) }
    }
}

@Composable
fun PagePanel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp), color = Panel, contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .05f))) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
    }
}

@Composable
fun catalogGridCells(): GridCells = GridCells.Adaptive(if (LocalConfiguration.current.fontScale > 1.15f) 140.dp else 104.dp)

@Composable
fun rootContentBottomPadding() = 108.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
