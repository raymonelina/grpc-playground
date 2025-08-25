#!/bin/bash

# Build script for Java projects
# Supports build, clean, and rebuild operations

set -e

# Source common utilities
source "$(dirname "$0")/common.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JAVA_DIR="$PROJECT_ROOT/java"

# Function to check if command exists


# Function to clean Java build artifacts
clean_java() {
    print_status "blue" "Cleaning Java build artifacts..."
    
    cd "$JAVA_DIR"
    
    # Clean Maven artifacts
    if [ -f "pom.xml" ] && command_exists mvn; then
        mvn clean >/dev/null 2>&1 || true
    fi
    
    # Clean Gradle artifacts
    if ([ -f "build.gradle" ] || [ -f "build.gradle.kts" ]) && command_exists gradle; then
        gradle clean >/dev/null 2>&1 || true
    fi
    
    # Manual cleanup of common directories
    rm -rf target/
    rm -rf build/
    rm -rf out/
    rm -rf .gradle/
    
    print_status "green" "Java clean completed"
}

# Check for Maven or Gradle
if [ -f "$JAVA_DIR/pom.xml" ]; then
    BUILD_TOOL="maven"
    if ! command_exists mvn; then
        echo "Error: Maven not found. Please install Maven."
        exit 1
    fi
elif [ -f "$JAVA_DIR/build.gradle" ] || [ -f "$JAVA_DIR/build.gradle.kts" ]; then
    BUILD_TOOL="gradle"
    if ! command_exists gradle; then
        echo "Error: Gradle not found. Please install Gradle."
        exit 1
    fi
else
    echo "No Maven or Gradle build file found. Creating basic Maven structure..."
    
    # Create basic Maven project structure
    mkdir -p "$JAVA_DIR/src/main/java"
    mkdir -p "$JAVA_DIR/src/test/java"
    
    # Create pom.xml
    cat > "$JAVA_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.example</groupId>
    <artifactId>grpc-ads-java</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    
    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <grpc.version>1.58.0</grpc.version>
        <protobuf.version>3.24.4</protobuf.version>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-netty-shaded</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-protobuf</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-stub</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>com.google.protobuf</groupId>
            <artifactId>protobuf-java</artifactId>
            <version>${protobuf.version}</version>
        </dependency>
        <dependency>
            <groupId>javax.annotation</groupId>
            <artifactId>javax.annotation-api</artifactId>
            <version>1.3.2</version>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.xolstice.maven.plugins</groupId>
                <artifactId>protobuf-maven-plugin</artifactId>
                <version>0.6.1</version>
                <configuration>
                    <protocArtifact>com.google.protobuf:protoc:${protobuf.version}:exe:${os.detected.classifier}</protocArtifact>
                    <pluginId>grpc-java</pluginId>
                    <pluginArtifact>io.grpc:protoc-gen-grpc-java:${grpc.version}:exe:${os.detected.classifier}</pluginArtifact>
                    <protoSourceRoot>${project.basedir}/../proto</protoSourceRoot>
                </configuration>
                <executions>
                    <execution>
                        <goals>
                            <goal>compile</goal>
                            <goal>compile-custom</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>kr.motd.maven</groupId>
                <artifactId>os-maven-plugin</artifactId>
                <version>1.7.1</version>
                <executions>
                    <execution>
                        <phase>initialize</phase>
                        <goals>
                            <goal>detect</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
EOF
    
    BUILD_TOOL="maven"
    echo "Created Maven project structure"
fi

# Function to build Java projects
build_java() {
    print_status "blue" "Building Java projects..."
    
    # Check for Maven or Gradle
    if [ -f "$JAVA_DIR/pom.xml" ]; then
        BUILD_TOOL="maven"
        if ! command_exists mvn; then
            print_status "red" "Maven not found. Please install Maven."
            exit 1
        fi
    elif [ -f "$JAVA_DIR/build.gradle" ] || [ -f "$JAVA_DIR/build.gradle.kts" ]; then
        BUILD_TOOL="gradle"
        if ! command_exists gradle; then
            print_status "red" "Gradle not found. Please install Gradle."
            exit 1
        fi
    else
        print_status "yellow" "No Maven or Gradle build file found. Creating basic Maven structure..."
        create_maven_project
        BUILD_TOOL="maven"
    fi
    
    # Build based on detected tool
    case $BUILD_TOOL in
        maven)
            print_status "blue" "Building with Maven..."
            cd "$JAVA_DIR"
            if mvn compile; then
                print_status "green" "Maven build completed successfully"
            else
                print_status "red" "Maven build failed"
                exit 1
            fi
            ;;
        gradle)
            print_status "blue" "Building with Gradle..."
            cd "$JAVA_DIR"
            if gradle build; then
                print_status "green" "Gradle build completed successfully"
            else
                print_status "red" "Gradle build failed"
                exit 1
            fi
            ;;
    esac
}

# Function to create Maven project structure
create_maven_project() {
    # Create basic Maven project structure
    mkdir -p "$JAVA_DIR/src/main/java"
    mkdir -p "$JAVA_DIR/src/test/java"
    
    # Create pom.xml
    cat > "$JAVA_DIR/pom.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.example</groupId>
    <artifactId>grpc-ads-java</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>
    
    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <grpc.version>1.58.0</grpc.version>
        <protobuf.version>3.24.4</protobuf.version>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-netty-shaded</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-protobuf</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>io.grpc</groupId>
            <artifactId>grpc-stub</artifactId>
            <version>${grpc.version}</version>
        </dependency>
        <dependency>
            <groupId>com.google.protobuf</groupId>
            <artifactId>protobuf-java</artifactId>
            <version>${protobuf.version}</version>
        </dependency>
        <dependency>
            <groupId>javax.annotation</groupId>
            <artifactId>javax.annotation-api</artifactId>
            <version>1.3.2</version>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.xolstice.maven.plugins</groupId>
                <artifactId>protobuf-maven-plugin</artifactId>
                <version>0.6.1</version>
                <configuration>
                    <protocArtifact>com.google.protobuf:protoc:${protobuf.version}:exe:${os.detected.classifier}</protocArtifact>
                    <pluginId>grpc-java</pluginId>
                    <pluginArtifact>io.grpc:protoc-gen-grpc-java:${grpc.version}:exe:${os.detected.classifier}</pluginArtifact>
                    <protoSourceRoot>${project.basedir}/../proto</protoSourceRoot>
                </configuration>
                <executions>
                    <execution>
                        <goals>
                            <goal>compile</goal>
                            <goal>compile-custom</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>kr.motd.maven</groupId>
                <artifactId>os-maven-plugin</artifactId>
                <version>1.7.1</version>
                <executions>
                    <execution>
                        <phase>initialize</phase>
                        <goals>
                            <goal>detect</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
EOF
    
    print_status "green" "Created Maven project structure"
}

# Main execution
main() {
    local action="${1:-build}"
    
    echo "=================================================="
    echo "gRPC Bidirectional Streaming - Java Build Script"
    echo "=================================================="
    print_status "blue" "Java directory: $JAVA_DIR"
    echo ""
    
    case "$action" in
        build)
            build_java
            ;;
        clean)
            clean_java
            ;;
        rebuild)
            print_status "blue" "Rebuilding Java projects (clean + build)..."
            clean_java
            echo ""
            build_java
            ;;
        help|--help|-h)
            print_usage
            ;;
        *)
            print_status "red" "Unknown action: $action"
            print_usage
            exit 1
            ;;
    esac
    
    print_status "green" "Java build script completed successfully!"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "ACTIONS:"
    echo "  build       - Build Java projects (default)"
    echo "  clean       - Clean build artifacts"
    echo "  rebuild     - Clean and rebuild projects"
    echo "  help        - Show this help message"
    echo ""
    echo "EXAMPLES:"
    echo "  $0              # Build Java projects"
    echo "  $0 clean        # Clean build artifacts"
    echo "  $0 rebuild      # Clean and rebuild"
}

main "$@"
