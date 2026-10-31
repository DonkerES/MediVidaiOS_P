MediVida iOS

MediVida es una aplicación móvil desarrollada en Swift y SwiftUI para iOS, diseñada para el seguimiento de la salud del paciente mediante la gestión de medicamentos, dosis, citas médicas, comidas y restricciones alimentarias.

Proyecto Universitario: Desarrollado por estudiantes de Tecnología en Telemática

Estructura:

MediVida_iOS/
├── MediVida/
│   ├── Assets.xcassets/
│   │   └── Recursos graficos, iconos y colores
│   ├── GoogleService-Info.plist
│   │   └── Configuracion de Firebase
│   └── MediVida/
│       ├── ContentView.swift
│       │   └── Pantallas principales, navegacion y estilos
│       ├── MediVidaApp.swift
│       │   └── Punto de entrada SwiftUI
│       ├── MediVidaAppDelegate.swift
│       │   └── Configuracion e inicializacion de Firebase
│       ├── MediVidaAuthStore.swift
│       │   └── Inicio, registro y sesion de usuario
│       ├── MediVidaAuthView.swift
│       │   └── Interfaz de autenticacion
│       ├── MediVidaAuthenticatedView.swift
│       │   └── Contenedor de la experiencia autenticada
│       ├── MediVidaStore.swift
│       │   └── Estado principal y persistencia local
│       └── MediVidaFirestoreRepository.swift
│           └── Lectura y escritura en Firestore
│
├── MediVidaCore/
│   ├── Models.swift
│   │   └── Modelos, horarios y reglas de programacion
│   ├── ProfileRules.swift
│   │   └── Validacion y reglas del perfil
│   ├── MediVidaSavedData.swift
│   │   └── Datos persistidos localmente
│   ├── MediVidaSyncCoordinator.swift
│   │   └── Coordinador central de sincronizacion
│   ├── MediVidaSyncRepository.swift
│   │   └── Contrato de acceso a datos remotos
│   ├── SyncMerge.swift
│   │   └── Combinacion de datos locales y remotos
│   ├── SyncQueueState.swift
│   │   └── Cola de cambios pendientes
│   └── SyncRetryProcessor.swift
│       └── Reintentos de escritura remota
│
└── MediVida.xcodeproj/
    ├── project.pbxproj
    │   └── Configuracion del proyecto Xcode
    ├── project.xcworkspace/
    │   └── Espacio de trabajo y dependencias
    └── xcuserdata/
        └── Configuracion personal de Xcode
