import type { InputHTMLAttributes } from "react";
import type { IconType } from "react-icons";
import "./Input.css";

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  Icon?: IconType;
  error?: string;
}

export const Input = ({ Icon, error, ...inputProps }: Props) => {
  return (
    <div className={`input-container ${Icon ? "has-icon" : ""}`}>
      {Icon && <Icon className="icon" />}
      <input type="text" {...inputProps} />
      {error && <span className="error">Error</span>}
    </div>
  );
};
