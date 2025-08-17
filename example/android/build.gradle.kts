buildscript {
    repositories {
        google()
        mavenCentral() // jcenter() is deprecated, use mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:7.2.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.6.10") // Directly specify version
    }
}

allprojects {
    repositories {
        google()
        mavenCentral() // jcenter() is deprecated, use mavenCentral()
    }
}

rootProject.buildDir = File("../build")

subprojects {
    project.buildDir = File("${rootProject.buildDir}/${project.name}")
}

subprojects {
    evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}