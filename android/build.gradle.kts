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

// mobile_scanner 3.5.7 自身仍按 android-33 编译，而它的 AndroidX 依赖要求
// compileSdk >= 34。这里把所有插件子工程的 compileSdk 统一到 36。
fun Project.forceCompileSdk36() {
    extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
        ?.compileSdkVersion(36)
}

subprojects {
    if (state.executed) {
        forceCompileSdk36()
    } else {
        afterEvaluate { forceCompileSdk36() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
