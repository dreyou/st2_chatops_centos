import eventlet
import httplib2
import libxml2
from pprint import pprint

from st2reactor.sensor.base import PollingSensor

def xcontent(node,xpath):
    res = ""
    try:
        value = node.xpathEval(xpath)
        if len(value) >=1:
            res = value[0].content
    except:
        res = ""
    return res

class ActivemqSensor(PollingSensor):
    def __init__(self, sensor_service, config):
        super(ActivemqSensor, self).__init__(sensor_service=sensor_service, config=config)
        self._logger = self._sensor_service.get_logger(name=self.__class__.__name__)
        self._stop = False
        self._logger.debug('ActivemqSensor init...')

    def setup(self):
        self._logger.debug('ActivemqSensor setup...')
        pass

    def poll(self):
        self.set_poll_interval(600)
        self._logger.debug('ActivemqSensor dispatching trigger...')
        if not self._config['activemq_servers_poll_enabled']:
            self._logger.debug('ActivemqSensor DISABLED')
            return
        for server in self._config.get('activemq_servers',[]):
            self.poll_server(server)
   
    def poll_server(self,server):
        activemq = httplib2.Http()
        activemq.add_credentials(server['user'], server['passwd'])
        resp, content = activemq.request(server['url'])
        self._logger.debug('ActivemqSensor trigger http get response: '+str(resp))
        doc = libxml2.recoverDoc(content)
        ctx = doc.xpathNewContext()
#        res = ctx.xpathEval("//queue[@name='queue.in.real']/stats/@consumerCount")
#        size = 0
#        if len(res) >=1:
#             size = res[0].content
        queues = ctx.xpathEval("//queue")
        for queue in queues:
            payload = {
                'name': xcontent(queue,'@name'),
                'size': int(xcontent(queue,'stats/@size')),
                'consumers': int(xcontent(queue,'stats/@consumerCount')),
                'enqueued': int(xcontent(queue,'stats/@enqueueCount')),
                'dequeued': int(xcontent(queue,'stats/@dequeueCount')),
                'url': server['url'],
                'comment': server['comment'],
            }
            self._sensor_service.dispatch(trigger='st2_chatops_misc.event1', payload=payload)

    def cleanup(self):
        self._stop = True

    # Methods required for programmable sensors.
    def add_trigger(self, trigger):
        pass

    def update_trigger(self, trigger):
        pass

    def remove_trigger(self, trigger):
        pass
