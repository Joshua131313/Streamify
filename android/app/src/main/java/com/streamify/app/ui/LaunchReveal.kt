package com.streamify.app.ui

import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.streamify.app.R

/** A brief brand reveal while the real screen loads underneath, never a network gate. */
@Composable
fun LaunchReveal(animate: Boolean, content: @Composable () -> Unit) {
    var finished by rememberSaveable { mutableStateOf(!animate || !ValueAnimator.areAnimatorsEnabled()) }
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        if (!finished) {
            progress.animateTo(1f, tween(850, easing = FastOutSlowInEasing))
            finished = true
        }
    }
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().then(if (!finished) Modifier.clearAndSetSemantics { } else Modifier)) { content() }
        if (!finished) {
            val p = progress.value
            val fade = ((p - .55f) / .45f).coerceIn(0f, 1f)
            Box(Modifier.fillMaxSize()
                .graphicsLayer { alpha = 1f - fade }
                .background(Color(0xFF0B0D10))
                .pointerInput(Unit) { awaitPointerEventScope { while (true) awaitPointerEvent().changes.forEach { it.consume() } } },
                contentAlignment = Alignment.Center) {
                Box(Modifier.size(260.dp).graphicsLayer {
                    alpha = kotlin.math.sin(p * Math.PI).toFloat() * .65f
                    scaleX = .7f + p * .4f; scaleY = scaleX
                }.background(Brush.radialGradient(listOf(Color(0x35FF3549), Color.Transparent))))
                Image(painterResource(R.drawable.streamify_logo), "Streamify",
                    Modifier.size(112.dp).graphicsLayer {
                        scaleX = 1f + .08f * p; scaleY = scaleX
                        translationY = -8.dp.toPx() * fade
                    })
            }
        }
    }
}
