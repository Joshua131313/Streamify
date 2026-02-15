import type { InputHTMLAttributes } from "react";
import type { IconType } from "react-icons";
import "./Input.css";

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  Icon?: IconType;
}

export const Input = ({ Icon, ...inputProps }: Props) => {
  return (
    <div className={`input-container ${Icon ? "has-icon" : ""}`}>
      {Icon && <Icon className="icon" />}
      <input type="text" {...inputProps} />
    </div>
  );
};
