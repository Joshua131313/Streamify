// src/components/ui/Loader/Loader.tsx
import "./Loader.css";

interface Props {
  fullScreen?: boolean;
  text?: string;
}

export const Loader = ({ fullScreen = false, text }: Props) => {
  return (
    <div className={`loader ${fullScreen ? "fullscreen" : ""}`}>
        {fullScreen && <div className="logo">Streamify</div>}
        <div className="spinner" />
        {text && <p className="loader-text">{text}</p>}
    </div>
  );
};
