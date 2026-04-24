allprojects {
    repositories {
        google()
        mavenCentral()
    }
    configurations.all {
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib:2.1.0")
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.1.0")
        resolutionStrategy.force("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.0")
        resolutionStrategy.force("androidx.concurrent:concurrent-futures:1.2.0")
    }
}

subprojects {
  afterEvaluate {
    if (project.hasProperty("android")) {
      project.dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
      project.extensions.configure<com.android.build.gradle.BaseExtension> {
        compileOptions {
          sourceCompatibility = JavaVersion.VERSION_17
          targetCompatibility = JavaVersion.VERSION_17
        }
      }
    }
    // Force Kotlin jvmTarget to match Java targetCompatibility (prevents
    // "Inconsistent JVM-target compatibility" errors from plugin subprojects)
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
      kotlinOptions {
        jvmTarget = "17"
      }
    }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
