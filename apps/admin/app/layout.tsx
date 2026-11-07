import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'JB Fitness · Operations', description: 'JB Fitness development dashboard' };
export default function Layout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
