import { AppImg } from "../ImgProxy/AppImg"

export const StaticLogo = () => {

    return (
         <div className="logo">
          <AppImg
            src="/logo/streamify-logo.png"
          />
          <span>Streamify</span>
        </div>
    )
}