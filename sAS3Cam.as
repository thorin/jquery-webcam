/**
* jQuery AS3 Webcam
*
* Copyright (c) 2014, Sergey Shilko (sergey.shilko@gmail.com)
*
* @author Sergey Shilko
* @see https://github.com/sshilko/jQuery-AS3-Webcam
*
**/

/* SWF external interface:
 * webcam.save()          - get base64 encoded JPEG image
 * webcam.saveAndPost()   - post JPEG image
 * webcam.pause()         - pause the camera
 * webcam.play()          - resume the camera
 * webcam.getCameraList() - get list of available cams
 * webcam.setCamera(i)    - set camera, camera index retrieved with getCameraList
 * webcam.getResolution() - get camera resolution actually applied
 * */

/* External triggers on events:
 * webcam.isClientReady() - you respond to SWF with true (by default) meaning javascript is ready to accept callbacks
 * webcam.cameraConnected() - camera connected callback from SWF
 * webcam.noCameraFound() - SWF response that it cannot find any suitable camera
 * webcam.cameraEnabled() - SWF response when camera tracking is enabled (this is called multiple times, use isCameraEnabled flag)
 * webcam.cameraDisabled()- SWF response, user denied usage of camera
 * webcam.error()         - Javascript failed to make call to SWF
 * webcam.debug()         - debug callback used from SWF and can be used from javascript side too
 * */

package {
    import flash.system.Security;
    import flash.system.SecurityPanel;

    import flash.external.ExternalInterface;

    import flash.display.Sprite;
    import flash.media.Camera;
    import flash.media.Video;
    import flash.display.BitmapData;
    import flash.events.*;
    import flash.utils.ByteArray;
    import flash.utils.Timer;
    import flash.net.*;

    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.StageQuality;

    import com.adobe.images.JPGEncoder;
    import com.dynamicflash.util.Base64;
    import com.jonas.net.Multipart;

    public class sAS3Cam extends Sprite {

        private var camera:Camera  = null;
        private var video:Video    = null;
        private var bmd:BitmapData = null;

        private var camBandwidth:int = 0; // Specifies the maximum amount of bandwidth that the current outgoing video feed can use, in bytes per second. To specify that Flash Player video can use as much bandwidth as needed to maintain the value of quality , pass 0 for bandwidth . The default value is 16384.
        private var camQuality:int = 100; // this value is 0-100 with 1 being the lowest quality. Pass 0 if you want the quality to vary to keep better framerates
        private var camFrameRate:int = 14;

        private var camResolution:Array;

        private function getCameraResolution():Array {
            var resolutionWidth:Number = this.loaderInfo.parameters["resolutionWidth"];
            var videoWidth:Number      = Math.floor(resolutionWidth);

            var resolutionHeight:Number = this.loaderInfo.parameters["resolutionHeight"];
            var videoHeight:Number      = Math.floor(resolutionHeight);

            var serverWidth:Number  = Math.floor(stage.stageWidth);
            var serverHeight:Number = Math.floor(stage.stageHeight);

            var result:Array = [Math.max(videoWidth, serverWidth), Math.max(videoHeight, serverHeight)];
            return result;
        }

        private function setupCamera(useCamera:Camera):void {
            useCamera.setMode(camResolution[0],
                              camResolution[1],
                              camFrameRate);

            camResolution[0] = useCamera.width;
            camResolution[1] = useCamera.height;
            camFrameRate     = useCamera.fps;

            useCamera.setQuality(camBandwidth, camQuality);
            useCamera.addEventListener(StatusEvent.STATUS, statusHandler);
            useCamera.setMotionLevel(100); //disable motion detection
        }

        private function setVideoCamera(useCamera:Camera):void {
            var doSmoothing:Boolean = this.loaderInfo.parameters["smoothing"];
            var doDeblocking:Number = this.loaderInfo.parameters["deblocking"];

            video = new Video(camResolution[0],camResolution[1]);
            video.smoothing  = doSmoothing;
            video.deblocking = doDeblocking;

            var ratio:Number  = video.width / video.height;

            video.width = Math.max(stage.stageWidth, stage.stageHeight * ratio);
            video.height = Math.max(stage.stageHeight, stage.stageWidth / ratio);
            video.x = (stage.stageWidth - video.width) / 2;
            video.y = (stage.stageHeight - video.height) / 2;
            video.attachCamera(useCamera);
            addChild(video);
        }

        public function sAS3Cam():void {
            flash.system.Security.allowDomain("*");
            stage.scaleMode = this.loaderInfo.parameters["StageScaleMode"];
            stage.quality = StageQuality.BEST;
            stage.align = this.loaderInfo.parameters["StageAlign"]; // empty string is absolute center

            camera = Camera.getCamera();

            if (null != camera) {
                if (ExternalInterface.available) {

                    camera = Camera.getCamera('0');
                    camResolution = getCameraResolution();
                    setupCamera(camera);
                    setVideoCamera(camera);

                    /**
                     * Dont use stage.width & stage.height because result image will be stretched
                     */
                    bmd = new BitmapData(camResolution[0], camResolution[1]);

                    try {
                        var containerReady:Boolean = isContainerReady();
                        if (containerReady) {
                            setupCallbacks();
                        }  else {
                            var readyTimer:Timer = new Timer(250);
                            readyTimer.addEventListener(TimerEvent.TIMER, timerHandler);
                            readyTimer.start();
                        }
                    } catch (err:Error) { } finally { }
                } else {

                }

            } else {
                extCall('noCameraFound');
            }
        }

        private function statusHandler(event:StatusEvent):void {
            if (event.code == "Camera.Unmuted") {
                camera.removeEventListener(StatusEvent.STATUS, statusHandler);
                extCall('cameraEnabled');
            } else {
                extCall('cameraDisabled');
            }
        }

        private function extCall(func:String, ...args):Boolean {
            var target:String = this.loaderInfo.parameters["callTarget"];
            return ExternalInterface.call(target + "." + func, args);
        }

        private function isContainerReady():Boolean {
            var result:Boolean = extCall("isClientReady");
            return result;
        }

        private function setupCallbacks():void {
            ExternalInterface.addCallback("setCamera", setCamera);
            ExternalInterface.addCallback("getCameraList", getCameraList);
            ExternalInterface.addCallback("getResolution", getResolution);
            ExternalInterface.addCallback("save", save);
            ExternalInterface.addCallback("saveAndPost", saveAndPost);
            ExternalInterface.addCallback("pause", pause);
            ExternalInterface.addCallback("playCam", playCam);
            extCall('cameraConnected');
            /* when we have pernament accept policy --> */
            if (!camera.muted) {
                extCall('cameraEnabled');
            } else {
                Security.showSettings(SecurityPanel.PRIVACY);
            }
            /* when we have pernament accept policy <-- */
        }

        private function timerHandler(event:TimerEvent):void {
            var isReady:Boolean = isContainerReady();
            if (isReady) {
                Timer(event.target).stop();
                setupCallbacks();
            }
        }

        /**
         * Returns actual resolution used by camera
         */
        public function getResolution():Array {
            var res:Array = [camResolution[0], camResolution[1]];
            return res;
        }

        public function getCameraList():Array {
            var list:Array = Camera.names;
            return list;
        }

        public function setCamera(id:String):Boolean {
            var newcam:Camera = Camera.getCamera(id.toString());
            if (newcam) {
                setupCamera(newcam);
                setVideoCamera(newcam);
                camera = newcam;
                return true;
            }
            return false;
        }

        public function save():String {
            bmd.draw(video);
            video.attachCamera(null); //this stops video stream, video will pause on last frame (like a preview)
            var quality:Number = 100;
            var byteArray:ByteArray = new JPGEncoder(quality).encode(bmd);
            var string:String = Base64.encodeByteArray(byteArray);
            return string;
        }

        public function saveAndPost(options:Object):void {
            bmd.draw(video);
            video.attachCamera(null); //this stops video stream, video will pause on last frame (like a preview)
            var quality:Number = 100;
            var byteArray:ByteArray = new JPGEncoder(quality).encode(bmd);

            // http://www.displayobject.fr/2012/08/03/posting-multipartform-data-using-as3/
            var form:Multipart = new Multipart(options.url);
            form.addFile(options.filefield, byteArray, "image/jpeg", options.filename);
            for (var name:String in options.data) {
                form.addField(name, options.data[name]);
            }

            var loader:URLLoader = new URLLoader();
            loader.addEventListener(Event.COMPLETE, function(evt:Event):void {
                ExternalInterface.call(options.js_callback, evt.target.data);
            });
            loader.load(form.request);
        }

        public function pause():void {
            video.attachCamera(null);
        }

        public function playCam():void {
            video.attachCamera(camera);
        }
    }
}
