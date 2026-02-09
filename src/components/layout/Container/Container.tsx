import { forwardRef } from "react";
import { AccentLine } from "../../ui/AccentLine/AccentLine"
import { Title } from "../../ui/Title/Title";
import "./Container.css"

interface Props {
    title?: string;
    children?: React.ReactNode;
    className?: string;
    containerId?: string;
    styled?: boolean;
}

export const Container = (props : Props) => {

    const { title, className, containerId, styled } = props

    return (
        <div  className={`app-container ${className}`} id={containerId}>
            {
            title && 
                <Title title={title}/>
            }
            <div className={`container-content ${styled ? "styled" : ""}`}>
                {props.children}
            </div>
        </div>
    )
}