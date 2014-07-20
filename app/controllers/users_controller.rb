require 'digest/sha2'
require 'openssl/cipher'
require 'base64'

class UsersController < ApplicationController
  before_action :set_user, :only => [:show, :edit, :update, :destroy]
  before_action :check_captcha, :only => [:create, :login, :update]

  respond_to :json, :xml, :html

  # GET /users
  def index
    if not session[:username]
      flash[:notice] = "Please login first"
      redirect_to :action => "login" and return
    end

    @users = User.includes(:addresses).all
    @users.each do |user|
      user.addresses.each do |addr|
        addr.balance = BitcoinRPC.new.getreceivedbyaddress addr.address
        addr.save! if addr.changed?
      end
    end
    respond_with @users
  end

  # GET /users/1
  def show
    @user = User.includes(:addresses).find params[:id]
    @user.addresses.each do |addr|
      addr.balance = BitcoinRPC.new.getreceivedbyaddress addr.address
      addr.save! if addr.changed?
    end
    respond_with @user
  end

  # GET /users/new
  def new
    @user = User.new
    respond_with @user
  end

  # GET /users/1/edit
  def edit
    @user = User.find params[:id]
    @user.password = nil
    respond_with @user
  end

  # POST /users
  def create
    if params[:user][:password] == ""
      flash[:notice] = "Password must be set"
      respond_with ret = { :status => 0 }, :status => :unauthorized do |format|
        format.html { redirect_to :back }
      end and return
    end

    @user = User.new user_params
    @user.save
    @address = @user.addresses.new.tap do |add|
      add.address = BitcoinRPC.new.getnewaddress @user.uuid
      add.balance = 0.0
      add.save
    end
    respond_with @user
  end

  # PATCH/PUT /users/1
  def update
    @user = User.find params[:id]
    @user.update user_params
    respond_with @user
  end

  # DELETE /users/1
  def destroy
    @user = User.find params[:id]
    @user.destroy
    respond_with @user
  end

  # GET /users/login
  def login
    begin
      @user = User.find_by_username(params[:username]).decrypt_password
    rescue
      @user = User.new
    end

    if params[:password] == @user.password
      session[:username] = params[:username]

      @user.password = nil
      respond_with @user, :status => :accepted do |format|
        format.html { redirect_to :action => 'index' }
      end

    else
      session[:username] = nil
      flash[:notice] = "Wrong account or password"

      respond_with ret = { :status => 0 }, :status => :unauthorized
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user
      @user = User.find params[:id]
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def user_params
      if params[:user][:password] != ""
        params.require(:user).permit(:username, :password, :email,
                                     addresses_attributes: [:address, :balance]
                                    ).encrypt_password
      else
        params.require(:user).permit(:username, :email,
                                     addresses_attributes: [:address, :balance])
      end
    end

    def check_captcha
      if action_name == 'login' and not params[:username]
        render and return
      end

      if params[:user] and params[:user][:captcha]
        params[:captcha] = params[:user][:captcha]
        params[:captcha_key] = params[:user][:captcha_key]
      end

      if not simple_captcha_valid?
        flash[:notice] = "Wrong Captcha"
        respond_with ret = { :status => 2 }, :status => :forbidden do |format|
          format.html { redirect_to :back }
        end and return
      end
    end

end
