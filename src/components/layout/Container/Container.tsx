import { forwardRef, useState } from "react";
import { AccentLine } from "../../ui/AccentLine/AccentLine"
import { Title } from "../../ui/Title/Title";
import "./Container.css"
import { Icon } from "../../ui/Icon/Icon";
import { FaMinus, FaPlus } from "react-icons/fa";

interface Props {
    title?: string;
    children?: React.ReactNode;
    className?: string;
    containerId?: string;
    styled?: boolean;
    accordionMode?: boolean;
}

export const Container = (props : Props) => {

    const { title, className, containerId, styled, accordionMode = false } = props
    const [expanded, setExpanded] = useState(false);

    return (
        <div  className={`app-container ${className}`} id={containerId}>
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
            <div className={`container-content ${styled ? "styled" : ""}`}>
                {(!accordionMode || expanded) && 
                    // if accordionMode enabled then it must be expanded to be visible
                    // so basically (propositional logic) p -> q; !p || q;
                    props.children
                }
            </div>
        </div>
    )
}