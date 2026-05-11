allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.isWarnings = false
        options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:-deprecation"))
    }

    if (name == "super_native_extensions") {
        tasks.withType<JavaCompile>().configureEach {
            doFirst {
                val dragDropHelper = project.file("src/main/java/com/superlist/super_native_extensions/DragDropHelper.java")
                val source = dragDropHelper.readText()
                val patched = source.replace(
                    "@SuppressWarnings(\"UnusedDeclaration\")",
                    "@SuppressWarnings({\"UnusedDeclaration\", \"deprecation\"})",
                )
                if (patched != source) {
                    dragDropHelper.writeText(patched)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
