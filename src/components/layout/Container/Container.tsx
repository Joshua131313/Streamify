import { useState } from "react";
import { Title } from "../../ui/Title/Title";
import "./Container.css"
import { Icon } from "../../ui/Icon/Icon";
import { FaMinus, FaPlus } from "react-icons/fa";
import { AppImg } from "../../ui/ImgProxy/AppImg";

interface Props {
    title?: string;
    children?: React.ReactNode;
    className?: string;
    containerId?: string;
    styled?: boolean;
    accordionMode?: boolean;
    defaultOpened?: boolean;
    backdropImg?: string;
}

export const Container = (props : Props) => {

    const { title, className, containerId, styled, accordionMode = false, backdropImg, defaultOpened = false } = props
    const [expanded, setExpanded] = useState(defaultOpened);

    return (
        <div className={`app-container ${className}`} id={containerId}>
            {
            title && 
                <div className="container-header flex-row sb ac" onClick={() => accordionMode && setExpanded(!expanded)}>
                    <Title title={title} />
                    {
                        accordionMode && 
                        <Icon 
                            Icon={expanded ? FaMinus : FaPlus} 
                        />
                    }
                </div>
            }
            {backdropImg && 
                <AppImg className="backdrop-img" src={backdropImg}/>
            }
            <div className={`container-content ${styled ? "styled" : ""}`}>
                {(!accordionMode || expanded) && 
                    props.children
                }
            </div>
    
        </div>
    )
}