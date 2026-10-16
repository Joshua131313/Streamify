package com.streamify.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SecondaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                    shape: Shape = androidx.compose.foundation.shape.CircleShape, border: BorderStroke? = null,
                    colors: ButtonColors = ButtonDefaults.buttonColors(),
                    contentPadding: PaddingValues = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                    content: @Composable RowScope.() -> Unit) {
    Button(onClick, modifier, enabled, shape = androidx.compose.foundation.shape.CircleShape, border = border,
        colors = colors.copy(containerColor = Color(0xFF2B2D32), contentColor = Color.White,
            disabledContainerColor = Color(0xFF23252A), disabledContentColor = Color(0xFF858991)),
        contentPadding = contentPadding) {
        ProvideTextStyle(MaterialTheme.typography.labelLarge.copy(fontSize = 16.sp)) { content() }
    }
}
