import QtQuick
import QtQuick.Controls
import QtTest
import "../../linux/gui" as Player

TestCase {
    name: "ZoomedSamplePosition"
    width: 600
    height: 500
    visible: true
    when: windowShown
    Rectangle { anchors.fill: parent; color: "#222529" }
    Player.SampleWaveform {
        id: waveform
        width: 580
        sample: ({frames:1000,start:0,end:250,left:[[0,0],[0,0.5],[-0.5,0],[0,0]]})
        zoom: 4
    }
    SignalSpy { id: requests; target: waveform; signalName: "request" }
    function test_move_changes_view_and_requests_new_slice() {
        let control=findChild(waveform,"samplePositionSlider");
        verify(control !== null);
        verify(control.enabled);
        control.forceActiveFocus();
        for (let i=0;i<8;i++) keyClick(Qt.Key_Right);
        verify(waveform.position > 0.5, JSON.stringify({position:waveform.position,value:control.value,focus:control.activeFocus,width:control.width,height:control.height}));
        verify(requests.count > 0);
        compare(control.value,waveform.position);
        grabImage(waveform).save("/source/.build/review-sample-waveform.png");
    }
}
