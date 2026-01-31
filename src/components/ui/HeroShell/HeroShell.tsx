interface Props {
  background: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

export const HeroShell = ({ background, children, className = "" }: Props) => {
  return (
    <div className={`hero-shell ${className}`}>

      {/* background */}
      {background}

      {/* overlay */}
      <div className="hero-overlay" />

      {/* content */}
      <div className="hero-shell-content">
        <div className="hero-shell-inner">
          {children}
        </div>
      </div>

    </div>
  );
};
