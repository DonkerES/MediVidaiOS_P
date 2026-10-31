MediVida iOS

MediVida es una aplicación móvil desarrollada en Swift y SwiftUI para iOS, diseñada para el seguimiento de la salud del paciente mediante la gestión de medicamentos, dosis, citas médicas, comidas y restricciones alimentarias.

Proyecto Universitario: Desarrollado por estudiantes de Tecnología en Telemática

Estructura:

MediVida_iOS/
├── MediVida/
│   ├── Assets.xcassets/                 # Recursos gráficos, iconos y colores
│   ├── GoogleService-Info.plist         # Configuración de Firebase
│   └── MediVida/
│       ├── `ContentView.swift`
│       │                                  # Pantallas principales, navegación y estilos
│       ├── `MediVidaApp.swift`
│       │                                  # Punto de entrada SwiftUI
│       ├── `MediVidaAppDelegate.swift`
│       │                                  # Configuración e inicialización de Firebase
│       ├── `MediVidaAuthStore.swift`
│       │                                  # Inicio, registro y sesión de usuario
│       ├── `MediVidaAuthView.swift`
│       │                                  # Interfaz de autenticación
│       ├── `MediVidaAuthenticatedView.swift`
│       │                                  # Contenedor de la experiencia autenticada
│       ├── `MediVidaStore.swift`
│       │                                  # Estado principal, persistencia y sincronización
│       └── `MediVidaFirestoreRepository.swift`
│                                          # Lectura y escritura en Firestore
│
├── MediVidaCore/
│   ├── `Models.swift`
│   │                                  # Modelos, horarios y reglas de programación
│   ├── `ProfileRules.swift`
│   │                                  # Validación y reglas del perfil
│   ├── `MediVidaSavedData.swift`
│   │                                  # Datos persistidos localmente
│   ├── `MediVidaSyncCoordinator.swift`
│   │                                  # Coordinador de sincronización de datos
│   ├── `MediVidaSyncRepository.swift`
│   │                                  # Contrato de acceso a datos remotos
│   ├── `SyncMerge.swift`
│   │                                  # Combinación entre datos locales y remotos
│   ├── `SyncQueueState.swift`
│   │                                  # Cola de cambios pendientes de sincronización
│   └── `SyncRetryProcessor.swift`
│                                      # Reintentos de escritura remota
│
└── MediVida.xcodeproj/
    ├── project.pbxproj                 # Configuración Xcode del proyecto
    ├── project.xcworkspace/            # Espacio de trabajo y dependencias
    └── xcuserdata/                    # Configuración personal de Xcode

