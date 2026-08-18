export default {
  content: [
  './index.html',
  './src/**/*.{js,ts,jsx,tsx}'
],
  theme: {
    extend: {
      colors: {
        ink: {
          DEFAULT: '#0D0D0D',
          soft: '#161616',
          muted: '#2A2A2A',
        },
        cream: {
          DEFAULT: '#FBF8F3',
          dark: '#F3EDE4',
        },
        brand: {
          50: '#FFF3EB',
          100: '#FFE1CC',
          200: '#FFC199',
          300: '#FF9F66',
          400: '#FA7F35',
          500: '#F2661C',
          600: '#D9520F',
          700: '#A93E0B',
        },
      },
      fontFamily: {
        display: ['Fraunces', 'Georgia', 'serif'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        xl: '0.875rem',
        '2xl': '1.25rem',
      },
      boxShadow: {
        card: '0 1px 2px rgba(13,13,13,0.04), 0 8px 24px -12px rgba(13,13,13,0.18)',
        lift: '0 18px 40px -18px rgba(13,13,13,0.35)',
      },
      keyframes: {
        'fade-in': {
          from: { opacity: '0' },
          to: { opacity: '1' },
        },
      },
      animation: {
        'fade-in': 'fade-in 200ms ease-out',
      },
    },
  },
  plugins: [],
}
