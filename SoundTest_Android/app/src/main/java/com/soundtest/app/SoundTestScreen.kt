package com.soundtest.app

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SoundTestScreen() {
    val looping = remember { mutableStateSetOf<SoundEvent>() }
    val voiceCounts = remember { mutableStateMapOf<SoundEvent, Int>() }
    val lastFilenames = remember { mutableStateMapOf<SoundEvent, String>() }

    LaunchedEffect(Unit) {
        while (true) {
            SoundEvent.entries.filter { it.maxVoices > 1 }.forEach { event ->
                voiceCounts[event] = AudioManager.shared.activeVoiceCount(event)
            }
            SoundEvent.entries.filter { it.variationCount > 1 }.forEach { event ->
                AudioManager.shared.lastPlayedFilename[event.rawValue]?.let {
                    lastFilenames[event] = it
                }
            }
            delay(100)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("AudioManager Test") },
                actions = {
                    TextButton(onClick = {
                        AudioManager.shared.stopAll()
                        looping.clear()
                    }) {
                        Text("Stop All", color = MaterialTheme.colorScheme.error)
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            contentPadding = PaddingValues(
                start = 16.dp, end = 16.dp,
                top = padding.calculateTopPadding() + 8.dp,
                bottom = 16.dp
            ),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            SoundEvent.categories.forEach { category ->
                item { SectionHeader(category) }
                SoundEvent.entries.filter { it.category == category }.forEach { event ->
                    item {
                        if (event.loops) {
                            LoopRow(event.displayName, event, looping)
                        } else {
                            SoundRow(event.displayName, event, voiceCounts, lastFilenames)
                        }
                    }
                }
            }

            item {
                Spacer(modifier = Modifier.height(8.dp))
                Button(
                    onClick = {
                        AudioManager.shared.stopAll()
                        looping.clear()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Stop All")
                }
            }
        }
    }
}


// MARK: - One-shot row

@Composable
private fun SoundRow(
    label: String,
    event: SoundEvent,
    voiceCounts: Map<SoundEvent, Int>,
    lastFilenames: Map<SoundEvent, String>
) {
    TextButton(
        onClick = { AudioManager.shared.play(event) },
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            lastFilenames[event]?.let { name ->
                Text(
                    name,
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (event.maxVoices > 1) {
            val count = voiceCounts[event] ?: 0
            val atLimit = count >= event.maxVoices
            Text(
                "$count/${event.maxVoices}",
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace,
                color = if (atLimit) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}


// MARK: - Loop toggle row

@Composable
private fun LoopRow(
    label: String,
    event: SoundEvent,
    looping: MutableSet<SoundEvent>
) {
    val isActive = event in looping
    TextButton(
        onClick = {
            if (isActive) {
                AudioManager.shared.stop(event)
                looping.remove(event)
            } else {
                AudioManager.shared.play(event)
                looping.add(event)
            }
        },
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Icon(
            imageVector = if (isActive) Icons.Default.CheckCircle else Icons.Default.PlayArrow,
            contentDescription = null,
            tint = if (isActive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary
        )
    }
}


// MARK: - Section header

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 16.dp, bottom = 2.dp)
    )
    HorizontalDivider()
}
