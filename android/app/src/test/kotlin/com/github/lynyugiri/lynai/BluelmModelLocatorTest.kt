package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class BluelmModelLocatorTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun resolvesConfigFileDirectly() {
        val root = temporaryFolder.root
        val config = File(root, BluelmModelLocator.CONFIG_FILE_NAME).apply {
            writeText("{}")
        }

        assertEquals(
            config.absolutePath,
            BluelmModelLocator.resolveConfigPath(config.absolutePath),
        )
    }

    @Test
    fun resolvesDirectoryAndNestedModelDirectory() {
        val root = temporaryFolder.root
        val direct = File(root, BluelmModelLocator.CONFIG_FILE_NAME).apply {
            writeText("{}")
        }
        assertEquals(
            direct.absolutePath,
            BluelmModelLocator.resolveConfigPath(root.absolutePath),
        )

        val nestedRoot = File(temporaryFolder.root, "nested-only").apply {
            mkdirs()
        }
        val nested = File(
            nestedRoot,
            "${BluelmModelLocator.NESTED_MODEL_DIR}/${BluelmModelLocator.CONFIG_FILE_NAME}",
        ).apply {
            parentFile!!.mkdirs()
            writeText("{}")
        }
        assertEquals(
            nested.absolutePath,
            BluelmModelLocator.resolveConfigPath(nestedRoot.absolutePath),
        )
    }

    @Test
    fun returnsNullForMissingPath() {
        assertNull(
            BluelmModelLocator.resolveConfigPath(
                File(temporaryFolder.root, "missing").absolutePath,
            ),
        )
    }

    @Test
    fun validationReportsMissingReferencedFiles() {
        val root = temporaryFolder.root
        val config = File(root, BluelmModelLocator.CONFIG_FILE_NAME).apply {
            writeText(minimalConfig())
        }
        File(root, "vocab.bin").writeText("vocab")
        File(root, "weights.bin").writeText("weights")

        val result = BluelmModelLocator.validate(config.absolutePath)

        assertFalse(result.valid)
        assertTrue(result.missingFiles.any { it == "embedding.bin" })
        assertEquals("v1", result.modelVersion)
    }

    @Test
    fun validationPassesWhenAllReferencedFilesExist() {
        val root = temporaryFolder.root
        val config = File(root, BluelmModelLocator.CONFIG_FILE_NAME).apply {
            writeText(minimalConfig())
        }
        listOf(
            "vocab.bin",
            "embedding.bin",
            "weights.bin",
            "overture.bin",
            "prompt.dla",
            "decode.dla",
            "vit.dla",
            "vit.bin",
        ).forEach { File(root, it).writeText("data") }

        val result = BluelmModelLocator.validate(config.absolutePath)

        assertTrue(result.error ?: "", result.valid)
        assertEquals(config.absolutePath, result.configPath)
        assertEquals("v1", result.modelVersion)
    }

    private fun minimalConfig(): String {
        return """
        {
          "llm_model": {
            "version": "v1",
            "vocab_bin": "vocab.bin",
            "embedding_bin": "embedding.bin",
            "share_weights_bins": ["weights.bin"],
            "base_params": [
              {
                "overture_bin": "overture.bin",
                "prompt_models": ["prompt.dla"],
                "decode_models": ["decode.dla"]
              }
            ]
          },
          "vit_model": {
            "model_clip_path": "vit.dla",
            "clip_sharedw_path": "vit.bin"
          }
        }
        """.trimIndent()
    }
}
