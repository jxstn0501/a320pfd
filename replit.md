# A320 Primary Flight Display (PFD) React Project

## Overview
This is a React-based simulation of an Airbus A320 Primary Flight Display (PFD). The application displays realistic aircraft instruments including artificial horizon, airspeed indicator, altimeter, and descent rate indicator with interactive controls for different input sources.

## Project Architecture
- **Framework**: React 16.1.1 with functional flight simulation
- **Technology Stack**: React, RxJS for reactive programming, SVG for aircraft instruments
- **Input Methods**: Keyboard, Gamepad/Joystick, and Device Gyroscope support
- **Real-time Updates**: Uses RxJS observables for smooth flight data streaming

## Project Structure
- `src/` - Main source directory
  - `inputs/` - Input handling modules (Keyboard, Gamepad, Gyroscope)
  - Component files for each instrument (Airspeed, Altimeter, Horizon, etc.)
  - `App.js` - Main application component with input selection
  - `Pfd.js` - Primary Flight Display container component

## Development Setup
- **Development Server**: Configured for Replit environment on port 5000
- **Host Configuration**: Set to 0.0.0.0 for proxy compatibility
- **Build System**: Create React App with custom webpack configuration

## Deployment Configuration
- **Target**: Autoscale deployment for static frontend
- **Build**: `npm run build` (creates optimized production build)
- **Serve**: Uses `serve` package to serve static files on port 5000

## Input Controls
1. **Keyboard**: WASD-style controls for pitch, roll, airspeed, altitude
2. **Gamepad**: Real joystick/controller support for realistic flight simulation
3. **Gyroscope**: Device orientation-based input for mobile devices

## Recent Changes
- ✅ Fixed RxJS import compatibility issues for modern environments
- ✅ Configured development server for Replit proxy environment
- ✅ Set up workflow for automatic development server management
- ✅ Configured deployment for production hosting

## User Preferences
- Legacy React project requiring careful dependency management
- Prioritize functionality over modernization to preserve original behavior
- Maintain existing flight simulation logic and instrument accuracy

## Known Issues
- Multiple React warnings related to missing keys and deprecated lifecycle methods
- Some unused variables and imports (legacy code preservation)
- Uses older versions of dependencies for compatibility