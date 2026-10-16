package com.streamify.app.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp

/** Native nested scrolling: ordinary scrolling wins until the top edge is reached. */
@Composable
fun PullDownDetail(state: LazyListState, dismiss: () -> Unit, content: @Composable (Modifier) -> Unit) {
    val threshold = with(LocalDensity.current) { 100.dp.toPx() }
    val drag = remember { Animatable(0f) }
    var offset by remember { mutableFloatStateOf(0f) }
    val currentDismiss by rememberUpdatedState(dismiss)
    val connection = remember(state, threshold) { object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (source != NestedScrollSource.UserInput) return Offset.Zero
            if ((available.y > 0 && !state.canScrollBackward) || offset > 0) {
                val old = offset
                offset = (offset + available.y * .65f).coerceIn(0f, threshold * 2)
                return if (old > 0 || available.y > 0) Offset(0f, available.y) else Offset.Zero
            }
            return Offset.Zero
        }
        override suspend fun onPreFling(available: Velocity): Velocity {
            if (offset <= 0) return Velocity.Zero
            if (offset >= threshold) { currentDismiss(); offset = 0f }
            else { drag.snapTo(offset); drag.animateTo(0f, spring()) { offset = value } }
            return available
        }
    } }
    Box(Modifier.fillMaxSize()) {
        content(Modifier.fillMaxSize().nestedScroll(connection).graphicsLayer {
            translationY = offset
            scaleX = 1f - (offset / threshold).coerceAtMost(1f)*.035f
            scaleY = scaleX
        })
    }
}
