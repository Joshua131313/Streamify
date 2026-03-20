import { FaLongArrowAltLeft } from "react-icons/fa"
import { Icon } from "../Icon/Icon"
import { createPortal } from "react-dom"
import { useEffect } from "react"
import "./AppPlayer.css"

interface Props {
    modal?: boolean;
    children?: React.ReactNode;
    cancelPlay: () => void;
    src: string;
}

export const AppPlayer = (props : Props) => {
    const { modal = true, children, cancelPlay, src } = props

    useEffect(() => {
        if(modal) {
            document.body.classList.add("player-open");
            const scrollY = window.scrollY;
            document.body.style.position = "fixed";
            document.body.style.top = `-${scrollY}px`;
            document.body.style.width = "100%";
            return () => {
                const scrollY = document.body.style.top;
                document.body.style.position = "";
                document.body.style.top = "";
                document.body.style.width = "";
                window.scrollTo(0, parseInt(scrollY || "0") * -1);
                document.body.classList.remove("player-open");
            };
        }
    }, [modal]);


    const Player = () => {
        return (
            <div className={`player ${modal ? "modal-player" : ""}`} role="dialog" aria-modal="true">
                {modal && <Icon className="back-icon player-control-icon" Icon={FaLongArrowAltLeft} onClick={cancelPlay}/>}
                {children}
                {children}
                <iframe 
                    src={src} 
                    allowFullScreen
                    
                />
            </div>
        )
    }

    return (
        modal ?
        createPortal(
            <Player />
        , document.body
        )
        : <Player />
    )
}