import os, socket, time
from datetime import datetime
from flask import Flask, jsonify, send_from_directory, request
from flask_swagger_ui import get_swaggerui_blueprint

app = Flask(__name__)

#DATA_SET = ['1', '2', '3'] # some data

START_TIME = time.time()

@app.route(f'/static/<path:path>')
def send_static(path):
    """set path to static files"""
    return send_from_directory('static', path)

@app.route("/live")
def live():
    return {"status": "alive"}, 200

@app.route("/")
def hello():
    html = "<h3>Hello Andy!!</h3>" \
           "<b>Hostname:</b> {hostname}<br/>" 

    return html.format(hostname=socket.gethostname())

@app.route('/test_get', methods=['GET'])
def test_get():
    return jsonify("this is a get response")

@app.route('/test_post', methods=['POST'])
def test_post():
    if request.is_json:
        data = request.get_json(force=True)
        return jsonify(f"item {data} added")
    else:
        return jsonify('incorret input, not json')

### swagger specific ###
SWAGGER_URL = '/api/docs'  # URL for exposing Swagger UI (without trailing '/')
API_URL = '/static/swagger/swagger.json'
# Call factory function to create our blueprint
swaggerui_blueprint = get_swaggerui_blueprint(
    SWAGGER_URL,  # Swagger UI static files will be mapped to '{SWAGGER_URL}/dist/'
    API_URL,
    config={  # Swagger UI config overrides
        'app_name': "Andy Swagger App"
    },

)
app.register_blueprint(swaggerui_blueprint)
### end swagger specific ###


#app.register_blueprint(request_api.get_blueprint())

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000, debug=True)