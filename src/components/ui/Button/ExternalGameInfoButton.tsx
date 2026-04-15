import React from "react";
import "./Button.css";
import { AppImg } from "../ImgProxy/AppImg";

interface Props {
    url: string;
    type?: "espn" | "espn-small" | "gamecenter"
}

const ExternalGameInfoButton: React.FC<Props> = ({ url, type = "espn" }) => {

    const imgSrc =
        type === "espn" ? "https://a.espncdn.com/redesign/assets/img/logos/logo-espn-82x20@2x.png" :
        type === "espn-small" ? "https://espnpressroom.com/us/files/2018/03/App-Icon-Android-8-150x150.png" :
        type === "gamecenter" ? "https://media.d3.nhle.com/image/private/t_q-best/prd/assets/nhl/logos/nhl_shield_on_dark_kl1omz" :
        ""

    return (
        <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className={`button external-btn ${type}`}
        >
            <AppImg src={imgSrc} alt="" />
        </a>
    );
};

export default ExternalGameInfoButton;