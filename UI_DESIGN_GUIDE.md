# v2ray Client - UI/UX Design Style Guide

This document defines the design system and aesthetic standards for the v2ray Flutter application. Developers should follow these guidelines to ensure visual consistency and a premium user experience across all platforms.

---

## Design Philosophy

The application follows an **ultra-minimal, dark, sophisticated** aesthetic. It is designed to feel professional and technical, prioritizing clarity and functionality.

**Key Principles**:
- **Minimalism**: No unnecessary decorations, gradients, or shadows.
- **Hierarchy through Opacity**: Use varying opacity levels of white to establish visual hierarchy.
- **Micro-interactions**: Subtle feedback for every user action.
- **Technical Precision**: Use monospace fonts for all raw data and identifiers.

---

## Color System

### Base Palette
| Role | Color | Hex Code |
| :--- | :--- | :--- |
| **Background** | Pure Black | `#000000` |
| **Surface** | Near-Black | `#0A0A0A` |
| **Accent / Primary** | Pure White | `#FFFFFF` |

### Semantic Colors
| Role | Color | Hex Code |
| :--- | :--- | :--- |
| **Success** | Neon Green | `#00FF88` |
| **Warning** | Caution Yellow | `#FFCC00` |
| **Error / Destructive** | Pink-Red | `#FF3366` |

### Text & Elements
- **Primary Text**: Pure white (`#FFFFFF`)
- **Secondary Text**: Medium gray (`#666666`)
- **Dividers**: Very dark gray (`#1A1A1A`)

---

## Typography

### Font Families
- **Primary**: `Inter` (Sans Serif)
- **Monospace**: Used for IP addresses, DNS records, and server configuration details.

### Text Styles
| Element | Size | Weight | Letter Spacing | Case |
| :--- | :--- | :--- | :--- | :--- |
| **App Title** | 20 | 900 | 2.0 | Uppercase |
| **Status Labels** | 10 | 600 | 1.2 | Uppercase |
| **Section Headers** | 12 | 900 | 2.0 | Uppercase |
| **Body (Strong)** | 14-16 | 600 | Normal | Mixed |
| **Body (Secondary)** | 11-12 | 400 | Normal | Mixed |
| **Button Labels** | 14 | 900 | 1.5 | Uppercase |

> [!TIP]
> Use **Letter Spacing** generously (1.0 - 2.0) for all uppercase labels and buttons to enhance readability and premium feel.

---

## Component Specifications

### Cards & Containers
- **Background**: `#0A0A0A` (Surface)
- **Border**: 1px solid `#1A1A1A` (or White at 5-10% opacity)
- **Corner Radius**: 12px
- **Elevation**: Always 0 (No shadows)

### Buttons

#### Main Action Button (CTA)
- **Height**: 64px
- **Corner Radius**: 16px
- **Idle Color**: Background: White | Text: Black
- **Active/Connected Color**: Background: Error Red | Text: Black
- **Disabled**: White at 5% opacity

#### Secondary / Outlined Button
- **Border**: 1px White at 10% opacity
- **Text**: White
- **Corner Radius**: 12px

### Form Inputs
- **Fill**: `#0A0A0A`
- **Border**: 1px White at 10% opacity (Active/Focused: 1px Pure White)
- **Corner Radius**: 12px
- **Content Padding**: 16px

---

## Layout & Spacing

### Grid & Alignment
- **Screen Padding**: 24px horizontal, 32px vertical
- **Inter-card Spacing**: 8px (vertical)
- **Section Spacing**: 32-48px

### Standard Units
- **Micro**: 4px
- **Base**: 8px
- **Double**: 16px
- **Quad**: 32px

---

## Interaction Patterns

### Visual Feedback
- **Taps**: Use `InkWell` with matching `borderRadius`.
- **Loading States**: Replace button text/icon with a centered `CircularProgressIndicator` (stroke width 2-3).
- **Selection**: 
    - 4px vertical white bar on the left edge of the selected item.
    - Background tint: White at 5% opacity.

### Selection States
When an item (e.g., a server) is selected:
- The border opacity increases to 20%.
- A vertical indicator bar appears.
- Font weight shifts to 600.

---

## Iconography
- **Preferred Style**: Outlined/Linear icons (Material Outlined).
- **Sizing**: 18-20px for list actions, 24px for primary UI controls.
- **Opacity**: 30% for decorative/secondary, 100% for active.

---

## Development Guidelines

1.  **Strictly No Shadows**: Use subtle borders (`1px`) to define depth and boundaries.
2.  **Opacity Control**: Use white with varying opacity for hierarchy rather than different shades of gray.
    - `0.05`: Surface tints / Disabled backgrounds
    - `0.10`: Subtle borders
    - `0.30`: Hint text / Secondary icons
    - `0.50`: Secondary text
    - `1.00`: Primary text
3.  **Consistency**: Always use the predefined `AppTheme` (see [app_theme.dart](file:///Users/danial/codes/v2ray_flutter_app/lib/theme/app_theme.dart)).
4.  **Monospace for Technical Data**: Ensure all network-related strings use a monospace font family for clarity.

---

**This design system ensures a technical, professional aesthetic that is modern and purpose-built for high-performance software.**
