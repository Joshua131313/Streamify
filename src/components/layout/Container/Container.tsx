import { AccentLine } from "../../ui/AccentLine/AccentLine"
import "./Container.css"

interface Props {
    title?: string;
    children?: React.ReactNode;
    className?: string;
    containerId?: string;
}

export const Container = (props : Props) => {

    const { title, className, containerId } = props

    return (
        <div className={`app-container ${className}`} id={containerId}>
            {
            title && 
                <div className="container-title">
                    <AccentLine />
                    <h1>{title}</h1>
                </div>
            }
            <div className="container-content">
                {props.children}
            </div>
        </div>
    )
}