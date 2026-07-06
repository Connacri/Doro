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
    plugins.withId("com.android.library") {
        val androidComponents = project.extensions.findByType(com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java)
        androidComponents?.finalizeDsl { dsl ->
            println("--- Doro Build Config: Finalizing library DSL for ${project.name}, setting compileSdk to 36")
            dsl.compileSdk = 36
        }
    }
    plugins.withId("com.android.application") {
        val androidComponents = project.extensions.findByType(com.android.build.api.variant.ApplicationAndroidComponentsExtension::class.java)
        androidComponents?.finalizeDsl { dsl ->
            println("--- Doro Build Config: Finalizing application DSL for ${project.name}, setting compileSdk to 36")
            dsl.compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
