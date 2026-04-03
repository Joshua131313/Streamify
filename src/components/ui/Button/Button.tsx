import type { ButtonHTMLAttributes } from "react"
import "./Button.css"
import { Loader } from "../Loader/Loader";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
    loading?: boolean;
}

export const Button = (props : Props) => {
    const { loading } = props;
    return (
        <button {...props} className={`button ${props.className}`} >
            {
                loading ? 
                <Loader />
                :
                props.children
            }
        </button>
    )
}