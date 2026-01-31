import type { IconType } from "react-icons"
import "./Icon.css"

interface Props {
    Icon: IconType;
    className?: string;
    onClick?: () => void;
}

export const Icon = ({Icon, className, onClick} : Props) => {
    
    return (
        <div className="app-icon" onClick={() => onClick && onClick()}>
            <Icon className={`${className}`}/>
        </div>
    )
}