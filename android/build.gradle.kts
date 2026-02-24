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

// Fix for old plugins that don't declare a namespace (required by AGP 8+).
subprojects {
    plugins.withId("com.android.library") {
        val ext = extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
        if (ext.namespace.isNullOrEmpty()) {
            // Read package from AndroidManifest.xml as fallback
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val pkg = Regex("""package="([^"]+)"""").find(manifest.readText())?.groupValues?.get(1)
                if (pkg != null) {
                    ext.namespace = pkg
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
